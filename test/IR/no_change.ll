; Multiplies that must be left alone.
; RUN: %sr_opt -passes=strength-reduce -S %s | FileCheck %s

; Not of the form 2^a +/- 2^b (11 = 0b1011, 100 = 0b1100100).
define i32 @mul11(i32 %x) {
; CHECK-LABEL: define i32 @mul11(
; CHECK-NEXT:    %r = mul i32 %x, 11
  %r = mul i32 %x, 11
  ret i32 %r
}

define i32 @mul100(i32 %x) {
; CHECK-LABEL: define i32 @mul100(
; CHECK-NEXT:    %r = mul i32 %x, 100
  %r = mul i32 %x, 100
  ret i32 %r
}

define i32 @mul_minus11(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus11(
; CHECK-NEXT:    %r = mul i32 %x, -11
  %r = mul i32 %x, -11
  ret i32 %r
}

; Trivial constants are left to InstSimplify.
define i32 @mul0(i32 %x) {
; CHECK-LABEL: define i32 @mul0(
; CHECK-NEXT:    %r = mul i32 %x, 0
  %r = mul i32 %x, 0
  ret i32 %r
}

define i32 @mul1(i32 %x) {
; CHECK-LABEL: define i32 @mul1(
; CHECK-NEXT:    %r = mul i32 %x, 1
  %r = mul i32 %x, 1
  ret i32 %r
}

; Neither operand is constant.
define i32 @var_var(i32 %x, i32 %y) {
; CHECK-LABEL: define i32 @var_var(
; CHECK-NEXT:    %r = mul i32 %x, %y
  %r = mul i32 %x, %y
  ret i32 %r
}

; Both operands constant: constant folding's job, not ours.
define i32 @const_const() {
; CHECK-LABEL: define i32 @const_const(
; CHECK-NEXT:    %r = mul i32 3, 5
  %r = mul i32 3, 5
  ret i32 %r
}

; Non-uniform vector constants are not splats.
define <2 x i32> @vec_non_splat(<2 x i32> %x) {
; CHECK-LABEL: define <2 x i32> @vec_non_splat(
; CHECK-NEXT:    %r = mul <2 x i32> %x, <i32 4, i32 8>
  %r = mul <2 x i32> %x, <i32 4, i32 8>
  ret <2 x i32> %r
}

; Only `mul` is touched.
define i32 @other_ops(i32 %x) {
; CHECK-LABEL: define i32 @other_ops(
; CHECK-NEXT:    %a = add i32 %x, 8
; CHECK-NEXT:    %b = sdiv i32 %a, 8
  %a = add i32 %x, 8
  %b = sdiv i32 %a, 8
  ret i32 %b
}
