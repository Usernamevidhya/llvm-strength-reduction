# LLVM Strength Reduction Pass

An out-of-tree LLVM plugin for the **new pass manager** that rewrites integer
`mul` by a constant into shifts and adds/subs.

| Constant `C`                         | Rewrite                                   |
|--------------------------------------|-------------------------------------------|
| `2^k`                                | `shl x, k`                                |
| `-2^k`                               | `0 - (x << k)`                            |
| `2^a + 2^b` (a > b)                  | `(x << a) + (x << b)`   (`x` if b = 0)    |
| `2^a - 2^b` (a > b)                  | `(x << a) - (x << b)`                     |
| `-(2^a - 2^b)`                       | `(x << b) - (x << a)`  (no extra negate)  |
| `-(2^a + 2^b)` (not also a run)      | `0 - ((x << a) + (x << b))`               |
| `-1`                                 | `0 - x`                                   |

Works for any integer width, constants on either side, and splat vector
constants. `0`, `1`, non-splat vectors, `const * const` and constants that are
not of the forms above (11, 100, ...) are left untouched.

## Layout

```
CMakeLists.txt                 find LLVM, build the plugin, `check-strength-reduction` target
src/StrengthReductionPass.cpp  the pass + plugin registration
samples/*.c                    powers of two / composite / negative constants
test/IR/*.ll                   lit + FileCheck tests on IR (and aarch64 asm)
test/Integration/*.test        lit + FileCheck tests driven from the C samples
scripts/build_and_run.sh       build, test, run on samples, aarch64 before/after comparison
scripts/verify_exhaustive.py   brute-force i8 semantic + overflow-flag verifier
scripts/push_to_github.sh      git init/add/commit/branch/remote/push automation
```

## Requirements

LLVM >= 15 (dev package incl. `llvm-config`, `opt`, `llc`, `FileCheck`, `not`),
`clang`, CMake >= 3.20, a C++17 compiler, and `pip install lit`. The
`llc` must include the AArch64 target. Linux and macOS (the plugin is not
set up for Windows). Developed and tested against LLVM 18.1.3.

Ubuntu/Debian: `sudo apt install llvm-18-dev llvm-18-tools clang-18 cmake ninja-build && pip install lit`

## Build and run

```bash
./scripts/build_and_run.sh            # build, run tests, run samples, print summary
./scripts/build_and_run.sh --clean    # from scratch
LLVM_CONFIG=/usr/lib/llvm-18/bin/llvm-config ./scripts/build_and_run.sh   # pick a specific LLVM
```

Manual:

```bash
cmake -S . -B build -DLLVM_DIR=$(llvm-config --cmakedir)
cmake --build build
PATH=$(llvm-config --bindir):$PATH cmake --build build --target check-strength-reduction
```

## Using the plugin

```bash
opt -load-pass-plugin=build/lib/StrengthReductionPass.so -passes=strength-reduce -S in.ll
clang -O2 -fpass-plugin=build/lib/StrengthReductionPass.so foo.c   # runs at OptimizerLast
```

Note: a function marked `optnone` (clang `-O0`) is skipped by `opt` like any
non-required pass. The scripts use `-O1 -Xclang -disable-llvm-passes` to get
unoptimised-but-not-`optnone` IR.

## Overflow flags (`nuw` / `nsw`)

Dropping a flag is always sound; keeping one is only sound if the new
instruction cannot be poison when the original `mul` was defined.

* `x * 2^k` -> one `shl`: `nuw` carries over exactly. `nsw` carries over only
  for positive `C`; for `INT_MIN` it must be dropped (`mul nsw 1, INT_MIN` is
  defined, `shl nsw 1, 31` is poison).
* `x * (2^a + 2^b)` (positive): every partial result is bounded by the final
  product, so `nuw`/`nsw` are valid on both shifts and the add.
* `sub` forms and anything negated: `x << a` can wrap even if `x * C` does
  not, so all flags are dropped.

`scripts/verify_exhaustive.py` checks this by brute force: all 256 i8
constants x constant on either side x 4 flag combinations x 256 inputs,
interpreting the output with LangRef poison semantics. (It was mutation-tested:
re-introducing the `INT_MIN` `nsw` bug makes it fail.)

## What to expect from the aarch64 comparison

`llc -mtriple=aarch64` at **-O0** does not strength-reduce constant multiplies
(except powers of two, which FastISel handles), so you see `mov + mul` become a
single shifted `add`/`sub`:

```
x*9 before (-O0):  mov w8, #9 ; mul w0, w0, w8
x*9 after  (-O0):  add w0, w0, w0, lsl #3
```

At **-O2** the AArch64 backend's DAG combiner already performs these
decompositions, so instruction counts are identical; the pass is neutral there.
Its value is making the IR itself cheaper/canonical for other IR-level
analyses, and for targets or pipelines where the backend does not do it.

## Publishing

```bash
./scripts/push_to_github.sh                 # create the empty GitHub repo first
./scripts/push_to_github.sh --force-remote  # if 'origin' points somewhere else
```
