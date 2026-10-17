//===- StrengthReductionPass.cpp - Mul-by-constant strength reduction ----===//
//
// An out-of-tree LLVM plugin (new pass manager) that rewrites
//
//     mul %x, C            (C a constant integer / splat vector constant)
//
// into cheaper shift / add / sub sequences:
//
//     C = 2^k                 ->  shl %x, k
//     C = -2^k                ->  sub 0, (shl %x, k)
//     C = 2^a + 2^b  (a > b)  ->  add (shl %x, a), (shl %x, b)
//     C = 2^a - 2^b  (a > b)  ->  sub (shl %x, a), (shl %x, b)
//     C = -(2^a - 2^b)        ->  sub (shl %x, b), (shl %x, a)   (no negate)
//     C = -(2^a + 2^b)        ->  sub 0, (add ...)   (only if not also 2^a' - 2^b')
//
// (a shift by b == 0 is simply %x, so e.g. 9 -> (x << 3) + x.)
//
// All reasoning is done on the *modular* bit pattern of the constant, so it
// is correct for every bit width and for both signed and unsigned users.
//
// Usage:
//   opt -load-pass-plugin=./StrengthReductionPass.so -passes=strength-reduce
//   clang -fpass-plugin=./StrengthReductionPass.so ...   (runs at OptimizerLast)
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Config/llvm-config.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/IR/Instruction.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/PatternMatch.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;
using namespace llvm::PatternMatch;

#define DEBUG_TYPE "strength-reduce"

namespace {

/// Result of trying to rewrite one multiply.
struct Rewrite {
  Value *NewValue = nullptr;
  explicit operator bool() const { return NewValue != nullptr; }
};

/// x << Amt (or just x when Amt == 0).  The shift amount is built with the
/// same shape as x (scalar or vector splat).
static Value *emitShl(IRBuilder<> &B, Value *X, unsigned Amt, bool NUW,
                      bool NSW) {
  if (Amt == 0)
    return X;
  return B.CreateShl(X, ConstantInt::get(X->getType(), Amt), "sr.shl", NUW,
                     NSW);
}

/// Attempt to expand `X * C`.  Pure decision logic runs first (APInt only);
/// instructions are emitted only once a rewrite is committed, so a failed
/// attempt never leaves dead code behind.
///
/// Overflow-flag policy (see README for the reasoning):
///  * C = 2^k as a single `shl`: `nuw` carries over exactly (the unsigned view
///    of C is 2^k); `nsw` carries over only when C > 0, since
///    `shl nsw x, 31` is stricter than `mul nsw x, INT_MIN`.
///  * C = 2^a + 2^b > 0: every partial result is bounded by the final one, so
///    both `nuw` and `nsw` are valid on the shifts and on the add.
///  * Everything else (subtractions, negations): intermediate values can wrap
///    even when the original multiply does not, so flags are dropped.
///    Dropping flags is always sound; it only makes the result less poisonous.
static Rewrite reduceMul(IRBuilder<> &B, Value *X, const APInt &C, bool NUW,
                         bool NSW) {
  // Nothing to do for 0 and 1 (InstSimplify's job).
  if (C.isZero() || C.isOne())
    return {};

  // x * -1  ->  0 - x
  if (C.isAllOnes())
    return {B.CreateNeg(X, "sr.neg")};

  // x * 2^k  ->  x << k.  isPowerOf2() looks at the raw bit pattern, so this
  // also catches INT_MIN (= 2^(W-1) modulo 2^W).
  if (C.isPowerOf2()) {
    bool KeepNSW = NSW && C.isStrictlyPositive();
    return {emitShl(B, X, C.logBase2(), NUW, KeepNSW)};
  }

  // From here on C is neither 0, 1, -1, nor INT_MIN-like, so |C| < 2^(W-1).
  const bool Negative = C.isNegative();
  const APInt A = Negative ? -C : C;

  // x * -2^k  ->  0 - (x << k)
  if (A.isPowerOf2())
    return {B.CreateNeg(emitShl(B, X, A.logBase2(), false, false), "sr.neg")};

  const APInt Low = A & -A;       // lowest set bit
  const APInt Rest = A & (A - 1); // A with lowest set bit cleared
  const unsigned LoBit = Low.logBase2();

  // A = 2^hi + 2^lo : exactly two bits set.
  const bool IsAddForm = Rest.isPowerOf2();

  // A = 2^hi - 2^lo : one contiguous run of one-bits (length >= 2).
  // A + Low carries through the run and lands on a single bit 2^hi.
  const APInt Carry = A + Low; // cannot wrap: A < 2^(W-1)
  const bool IsSubForm = Carry.isPowerOf2();

  // For a negative C the sub form is strictly better when it applies: since
  //   x * -(2^hi - 2^lo) == (x << lo) - (x << hi)
  // the negation is absorbed by swapping the sub's operands.  (E.g. -3 becomes
  // x - (x << 2): 2 instructions instead of -((x << 1) + x): 3.)
  const bool UseSub = IsSubForm && (Negative || !IsAddForm);

  if (UseSub) {
    const unsigned HiBit = Carry.logBase2();
    Value *Hi = emitShl(B, X, HiBit, false, false);
    Value *Lo = emitShl(B, X, LoBit, false, false);
    return {Negative ? B.CreateSub(Lo, Hi, "sr.sub")
                     : B.CreateSub(Hi, Lo, "sr.sub")};
  }

  if (IsAddForm) {
    const unsigned HiBit = Rest.logBase2();
    const bool Flags = !Negative; // see policy above
    Value *Hi = emitShl(B, X, HiBit, Flags && NUW, Flags && NSW);
    Value *Lo = emitShl(B, X, LoBit, Flags && NUW, Flags && NSW);
    Value *Sum = B.CreateAdd(Hi, Lo, "sr.add", Flags && NUW, Flags && NSW);
    return {Negative ? B.CreateNeg(Sum, "sr.neg") : Sum};
  }

  return {}; // not of the form we handle
}

struct StrengthReductionPass : PassInfoMixin<StrengthReductionPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &) {
    // Collect first: we mutate the IR while processing.
    SmallVector<BinaryOperator *, 16> Worklist;
    for (BasicBlock &BB : F)
      for (Instruction &I : BB)
        if (auto *BO = dyn_cast<BinaryOperator>(&I))
          if (BO->getOpcode() == Instruction::Mul)
            Worklist.push_back(BO);

    bool Changed = false;
    IRBuilder<> Builder(F.getContext());

    for (BinaryOperator *Mul : Worklist) {
      // Accept the constant on either side (mul is commutative).
      Value *X = nullptr;
      const APInt *C = nullptr;
      if (match(Mul->getOperand(1), m_APInt(C)))
        X = Mul->getOperand(0);
      else if (match(Mul->getOperand(0), m_APInt(C)))
        X = Mul->getOperand(1);
      else
        continue;

      // const * const is constant folding's job.
      if (isa<Constant>(X))
        continue;

      // SetInsertPoint(Instruction*) also adopts the debug location.
      Builder.SetInsertPoint(Mul);
      Rewrite R = reduceMul(Builder, X, *C, Mul->hasNoUnsignedWrap(),
                            Mul->hasNoSignedWrap());
      if (!R)
        continue;

      LLVM_DEBUG(dbgs() << "strength-reduce: " << *Mul << "\n  -> "
                        << *R.NewValue << "\n");

      if (auto *NewI = dyn_cast<Instruction>(R.NewValue))
        NewI->takeName(Mul);
      Mul->replaceAllUsesWith(R.NewValue);
      Mul->eraseFromParent();
      Changed = true;
    }

    if (!Changed)
      return PreservedAnalyses::all();
    PreservedAnalyses PA;
    PA.preserveSet<CFGAnalyses>(); // we never touch the CFG
    return PA;
  }
};

} // end anonymous namespace

//===----------------------------------------------------------------------===//
// Plugin registration
//===----------------------------------------------------------------------===//

extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "StrengthReduction", "1.0.0",
          [](PassBuilder &PB) {
            // opt -passes=strength-reduce
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "strength-reduce") {
                    FPM.addPass(StrengthReductionPass());
                    return true;
                  }
                  return false;
                });

            // clang -fpass-plugin=...  /  opt -O2 -load-pass-plugin=...
            // Run late so InstCombine does not undo the expansion.  The
            // variadic generic lambda keeps this source-compatible with LLVM
            // versions whose callback has an extra ThinOrFullLTOPhase arg.
            PB.registerOptimizerLastEPCallback(
                [](ModulePassManager &MPM, auto &&...) {
                  MPM.addPass(createModuleToFunctionPassAdaptor(
                      StrengthReductionPass()));
                });
          }};
}
