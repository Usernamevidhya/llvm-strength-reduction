#!/usr/bin/env python3
"""Exhaustively verify the strength-reduction pass on i8 multiplies.

For every constant C in [-128, 127] (all 256 bit patterns), every placement of
the constant (lhs / rhs) and every overflow-flag combination (none / nuw / nsw
/ nuw nsw) this script:

  1. emits `mul [flags] i8 %x, C` into a module,
  2. runs `opt -passes=strength-reduce` over it,
  3. interprets the resulting straight-line IR for all 256 values of %x,
     tracking poison exactly as the LangRef defines it for shl/add/sub/mul.

The refinement rule being checked: whenever the ORIGINAL multiply yields a
defined value, the TRANSFORMED code must yield the same defined value (so the
flags the pass keeps are sound).  Where the original is poison anything goes.

Usage: verify_exhaustive.py --plugin build/lib/StrengthReductionPass.so [--opt opt]
Exit status is non-zero on any mismatch.
"""
import argparse
import itertools
import re
import subprocess
import sys

W = 8
MASK = (1 << W) - 1
POISON = None


def to_signed(v):
    return v - (1 << W) if v & (1 << (W - 1)) else v


def binop(op, a, b, nuw, nsw):
    """Evaluate an i8 binop; a, b are unsigned ints or POISON."""
    if a is POISON or b is POISON:
        return POISON
    if op == "shl":
        if b >= W:
            return POISON
        full_u = a << b
        res = full_u & MASK
        if nuw and full_u != res:
            return POISON
        if nsw and (to_signed(a) << b) != to_signed(res):
            return POISON
        return res
    if op == "add":
        full_u, full_s = a + b, to_signed(a) + to_signed(b)
    elif op == "sub":
        full_u, full_s = a - b, to_signed(a) - to_signed(b)
    elif op == "mul":
        full_u, full_s = a * b, to_signed(a) * to_signed(b)
    else:
        raise ValueError(op)
    res = full_u & MASK
    if nuw and full_u != res:
        return POISON
    if nsw and full_s != to_signed(res):
        return POISON
    return res


INSTR = re.compile(
    r"^\s*%(?P<dst>[\w.]+)\s*=\s*(?P<op>shl|add|sub|mul)\s+(?P<flags>(?:nuw\s+|nsw\s+)*)"
    r"i8\s+(?P<a>%?[\w.-]+),\s*(?P<b>%?[\w.-]+)\s*$")
RET = re.compile(r"^\s*ret\s+i8\s+(?P<v>%?[\w.-]+)\s*$")
DEFINE = re.compile(r"^define\s.*@(?P<name>\w+)\(")


def parse_functions(ir):
    funcs, cur = {}, None
    for line in ir.splitlines():
        m = DEFINE.match(line)
        if m:
            cur = funcs.setdefault(m["name"], {"body": [], "ret": None})
            continue
        if cur is None:
            continue
        if line.startswith("}"):
            cur = None
            continue
        m = INSTR.match(line)
        if m:
            fl = m["flags"].split()
            cur["body"].append((m["dst"], m["op"], "nuw" in fl, "nsw" in fl, m["a"], m["b"]))
            continue
        m = RET.match(line)
        if m:
            cur["ret"] = m["v"]
            continue
        s = line.strip()
        if s and not s.startswith((";", "entry:", "ret")):
            raise RuntimeError("unparsed line: %r" % line)
    return funcs


def run_func(fn, x):
    env = {"x": x}

    def val(tok):
        if tok.startswith("%"):
            return env[tok[1:]]
        return int(tok) & MASK

    for dst, op, nuw, nsw, a, b in fn["body"]:
        env[dst] = binop(op, val(a), val(b), nuw, nsw)
    return val(fn["ret"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugin", required=True)
    ap.add_argument("--opt", default="opt")
    args = ap.parse_args()

    flag_sets = ["", "nuw ", "nsw ", "nuw nsw "]
    cases, lines = [], []
    for c, side, flags in itertools.product(range(-128, 128), ("rhs", "lhs"), flag_sets):
        name = "f_%s_%s_%s" % (("m%d" % -c) if c < 0 else str(c), side,
                               flags.replace(" ", "") or "none")
        a, b = ("%x", str(c)) if side == "rhs" else (str(c), "%x")
        lines.append("define i8 @%s(i8 %%x) {\n  %%r = mul %si8 %s, %s\n  ret i8 %%r\n}\n"
                     % (name, flags, a, b))
        cases.append((name, c, flags))
    src = "\n".join(lines)

    out = subprocess.run(
        [args.opt, "-load-pass-plugin=" + args.plugin, "-passes=strength-reduce", "-S"],
        input=src, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("opt failed:\n" + out.stderr)
    before, after = parse_functions(src), parse_functions(out.stdout)

    reduced = failures = 0
    for name, c, flags in cases:
        b, a = before[name], after[name]
        if len(a["body"]) != 1 or a["body"][0][1] != "mul":
            reduced += 1
        for x in range(1 << W):
            want, got = run_func(b, x), run_func(a, x)
            if want is POISON:
                continue
            if got is POISON or got != want:
                failures += 1
                if failures <= 10:
                    print("MISMATCH %s: x=%d (%d) orig=%s new=%s\n  new body: %s"
                          % (name, x, to_signed(x), want,
                             "poison" if got is POISON else got, a["body"]))

    print("checked %d functions x %d inputs; %d were rewritten; %d failures"
          % (len(cases), 1 << W, reduced, failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
