#!/usr/bin/env bash
#
# Build the strength-reduction plugin and run it against samples/*.c.
#
# For every sample this script
#   1. compiles C -> unoptimised LLVM IR for aarch64 (clang, no LLVM passes),
#   2. runs `opt -passes=mem2reg` (baseline "before") and then the plugin
#      (`-passes=strength-reduce`, "after"),
#   3. runs `llc -mtriple=aarch64` on both, at -O0 and -O2, and compares
#      static instruction / `mul` counts,
#   4. builds host executables from the before/after IR, runs both and checks
#      that their output is identical.
# It also runs the lit/FileCheck suite and the exhaustive i8 verifier.
#
# Usage:  scripts/build_and_run.sh [options]
#   --llvm-dir DIR   directory containing LLVMConfig.cmake
#                    (default: from $LLVM_DIR or `llvm-config --cmakedir`)
#   --build-dir DIR  CMake build directory   (default: <repo>/build)
#   --out-dir DIR    where IR / asm are written (default: <repo>/out)
#   --clean          wipe build and out dirs first
#   --no-tests       skip lit and the exhaustive verifier
#   -h, --help       show this help
#
# Environment: LLVM_CONFIG=/path/to/llvm-config  to pick a specific LLVM.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
OUT_DIR="$REPO_ROOT/out"
LLVM_DIR_ARG="${LLVM_DIR:-}"
CLEAN=0
RUN_TESTS=1

die()  { echo "error: $*" >&2; exit 1; }
info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --llvm-dir)  LLVM_DIR_ARG="${2:?--llvm-dir needs a value}"; shift 2 ;;
    --build-dir) BUILD_DIR="${2:?--build-dir needs a value}"; shift 2 ;;
    --out-dir)   OUT_DIR="${2:?--out-dir needs a value}"; shift 2 ;;
    --clean)     CLEAN=1; shift ;;
    --no-tests)  RUN_TESTS=0; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Locate LLVM
# ---------------------------------------------------------------------------
find_llvm_config() {
  if [[ -n "${LLVM_CONFIG:-}" ]]; then echo "$LLVM_CONFIG"; return; fi
  if [[ -n "$LLVM_DIR_ARG" && -x "$LLVM_DIR_ARG/../../../bin/llvm-config" ]]; then
    echo "$LLVM_DIR_ARG/../../../bin/llvm-config"; return
  fi
  local c
  for c in llvm-config llvm-config-21 llvm-config-20 llvm-config-19 llvm-config-18 \
           llvm-config-17 llvm-config-16 llvm-config-15 \
           /opt/homebrew/opt/llvm/bin/llvm-config /usr/local/opt/llvm/bin/llvm-config; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
    [[ -x "$c" ]] && { echo "$c"; return; }
  done
  return 1
}

LLVM_CONFIG_BIN="$(find_llvm_config)" || die "llvm-config not found. Install LLVM >= 15 dev packages, or set LLVM_CONFIG / --llvm-dir."
LLVM_BIN="$("$LLVM_CONFIG_BIN" --bindir)"
LLVM_VER="$("$LLVM_CONFIG_BIN" --version)"
[[ -z "$LLVM_DIR_ARG" ]] && LLVM_DIR_ARG="$("$LLVM_CONFIG_BIN" --cmakedir)"
(( ${LLVM_VER%%.*} >= 15 )) || die "LLVM $LLVM_VER is too old; need >= 15."

pick_tool() {  # pick_tool <name>: prefer the bindir matching llvm-config
  if [[ -x "$LLVM_BIN/$1" ]]; then echo "$LLVM_BIN/$1"
  elif command -v "$1" >/dev/null 2>&1; then command -v "$1"
  else return 1; fi
}
CLANG="$(pick_tool clang)" || die "clang not found in $LLVM_BIN or PATH"
OPT="$(pick_tool opt)"     || die "opt not found in $LLVM_BIN or PATH"
LLC="$(pick_tool llc)"     || die "llc not found in $LLVM_BIN or PATH"
"$LLC" --version | grep -qi aarch64 || die "this llc was built without the AArch64 target"
command -v cmake >/dev/null || die "cmake not found"

info "Toolchain"
echo "LLVM      : $LLVM_VER ($LLVM_DIR_ARG)"
echo "clang/opt/llc: $CLANG / $OPT / $LLC"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if (( CLEAN )); then info "Cleaning"; rm -rf "$BUILD_DIR" "$OUT_DIR"; fi

GEN=()
command -v ninja >/dev/null && GEN=(-G Ninja)

info "Configuring and building the plugin"
cmake -S "$REPO_ROOT" -B "$BUILD_DIR" "${GEN[@]}" -DLLVM_DIR="$LLVM_DIR_ARG" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" --parallel

PLUGIN="$(find "$BUILD_DIR" -name 'StrengthReductionPass.*' \( -name '*.so' -o -name '*.dylib' -o -name '*.dll' \) | head -n1)"
[[ -f "$PLUGIN" ]] || die "plugin binary not found under $BUILD_DIR"
echo "plugin    : $PLUGIN"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if (( RUN_TESTS )); then
  info "lit / FileCheck tests"
  if command -v lit >/dev/null 2>&1 || command -v llvm-lit >/dev/null 2>&1; then
    # Put the matching LLVM tools first so FileCheck/opt/clang are consistent.
    PATH="$LLVM_BIN:$PATH" cmake --build "$BUILD_DIR" --target check-strength-reduction
  else
    warn "lit not installed (pip install lit); skipping lit tests"
  fi

  info "Exhaustive i8 verification (values + overflow-flag soundness)"
  if command -v python3 >/dev/null 2>&1; then
    python3 "$REPO_ROOT/scripts/verify_exhaustive.py" --plugin "$PLUGIN" --opt "$OPT"
  else
    warn "python3 not found; skipping exhaustive verification"
  fi
fi

# ---------------------------------------------------------------------------
# Run against the sample programs
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"

# Count real instructions in an assembly listing: indented lines that do not
# start with '.' (directive) or '//' (comment).
count_insns() { grep -Ecv '^([^[:space:]]|[[:space:]]*(\.|//|$))' "$1" || true; }
# Count multiply-family instructions (mul, madd, smull, umull, mneg, msub...).
count_muls()  { grep -Ec '^[[:space:]]+(mul|madd|msub|mneg|smull|umull|smaddl|umaddl)[[:space:]]' "$1" || true; }

emit_ir() {  # emit_ir <src.c> <out.ll> [extra clang flags...]
  local src="$1" out="$2"; shift 2
  "$CLANG" "$@" -O1 -Xclang -disable-llvm-passes -fno-discard-value-names \
           -S -emit-llvm "$src" -o - | "$OPT" -passes=mem2reg -S -o "$out"
}

SUMMARY=()
STATUS=0
shopt -s nullglob
SAMPLES=("$REPO_ROOT"/samples/*.c)
(( ${#SAMPLES[@]} )) || die "no samples found in $REPO_ROOT/samples"

for src in "${SAMPLES[@]}"; do
  name="$(basename "$src" .c)"
  d="$OUT_DIR/$name"; mkdir -p "$d"
  info "Sample: $name"

  # --- aarch64 IR, before / after ------------------------------------------
  emit_ir "$src" "$d/before.ll" --target=aarch64-linux-gnu
  "$OPT" -load-pass-plugin="$PLUGIN" -passes=strength-reduce -S "$d/before.ll" -o "$d/after.ll"

  muls_ir_before=$(grep -Ec '= mul ' "$d/before.ll" || true)
  muls_ir_after=$(grep -Ec '= mul ' "$d/after.ll" || true)
  echo "IR  mul instructions: before=$muls_ir_before after=$muls_ir_after"

  # --- static assembly via llc -mtriple=aarch64 ------------------------------
  for lvl in O0 O2; do
    "$LLC" -mtriple=aarch64 "-$lvl" "$d/before.ll" -o "$d/before.$lvl.s" 2>/dev/null
    "$LLC" -mtriple=aarch64 "-$lvl" "$d/after.ll"  -o "$d/after.$lvl.s"  2>/dev/null
    b_i=$(count_insns "$d/before.$lvl.s"); a_i=$(count_insns "$d/after.$lvl.s")
    b_m=$(count_muls  "$d/before.$lvl.s"); a_m=$(count_muls  "$d/after.$lvl.s")
    printf 'asm -%s: instructions %4d -> %-4d (%+d)   mul/madd %3d -> %-3d\n' \
           "$lvl" "$b_i" "$a_i" "$((a_i - b_i))" "$b_m" "$a_m"
    SUMMARY+=("$(printf '%-22s %-3s %6d %6d %+6d   %5d %5d' "$name" "$lvl" "$b_i" "$a_i" "$((a_i - b_i))" "$b_m" "$a_m")")
  done

  # --- behavioural check on the host ---------------------------------------
  # Same transformation, host triple, real executables, compare outputs.
  if emit_ir "$src" "$d/host.before.ll" 2>/dev/null &&
     "$OPT" -load-pass-plugin="$PLUGIN" -passes=strength-reduce -S "$d/host.before.ll" -o "$d/host.after.ll" &&
     "$CLANG" -w "$d/host.before.ll" -o "$d/run.before" 2>/dev/null &&
     "$CLANG" -w "$d/host.after.ll"  -o "$d/run.after"  2>/dev/null; then
    out_b="$("$d/run.before")"; out_a="$("$d/run.after")"
    if [[ "$out_b" == "$out_a" ]]; then
      echo "run      : outputs identical -> $out_a"
    else
      echo "run      : OUTPUT MISMATCH" >&2
      echo "  before: $out_b" >&2; echo "  after : $out_a" >&2
      STATUS=1
    fi
  else
    warn "could not build host executables for $name; skipping the run comparison"
  fi
done

info "Summary: aarch64 static instruction counts (llc -mtriple=aarch64)"
printf '%-22s %-3s %6s %6s %6s   %5s %5s\n' sample opt before after delta "mul-b" "mul-a"
printf '%s\n' "${SUMMARY[@]}"
cat <<EOF

Artifacts (IR + assembly) are in: $OUT_DIR
Note: at -O2 the AArch64 backend already strength-reduces many constant
multiplies itself, so the largest differences show up at -O0, where it does not.
EOF

exit "$STATUS"
