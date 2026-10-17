; Negative multipliers.
; RUN: %sr_opt -passes=strength-reduce -S %s | FileCheck %s

define i32 @mul_minus1(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus1(
; CHECK-NEXT:    %r = sub i32 0, %x
  %r = mul i32 %x, -1
  ret i32 %r
}

; -8 = -(2^3)
define i32 @mul_minus8(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus8(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %r = sub i32 0, %sr.shl
  %r = mul i32 %x, -8
  ret i32 %r
}

; -3 = -(2^2 - 2^0)... i.e. 2^0 - 2^2 : sub form, no negate (2 insns, not 3).
define i32 @mul_minus3(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus3(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 2
; CHECK-NEXT:    %r = sub i32 %x, %sr.shl
  %r = mul i32 %x, -3
  ret i32 %r
}

; -12 = 2^2 - 2^4 : also a contiguous run, so no negate.
define i32 @mul_minus12(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus12(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 4
; CHECK-NEXT:    %sr.shl1 = shl i32 %x, 2
; CHECK-NEXT:    %r = sub i32 %sr.shl1, %sr.shl
  %r = mul i32 %x, -12
  ret i32 %r
}

; -5 = -(2^2 + 2^0): two bits but NOT a run, so the add form + negate is used.
define i32 @mul_minus5(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus5(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 2
; CHECK-NEXT:    %sr.add = add i32 %sr.shl, %x
; CHECK-NEXT:    %r = sub i32 0, %sr.add
  %r = mul i32 %x, -5
  ret i32 %r
}

; -20 = -(2^4 + 2^2)
define i32 @mul_minus20(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus20(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 4
; CHECK-NEXT:    %sr.shl1 = shl i32 %x, 2
; CHECK-NEXT:    %sr.add = add i32 %sr.shl, %sr.shl1
; CHECK-NEXT:    %r = sub i32 0, %sr.add
  %r = mul i32 %x, -20
  ret i32 %r
}

; -7 = -(2^3 - 2^0) = 2^0 - 2^3 : operands swapped, no extra negate.
define i32 @mul_minus7(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus7(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %r = sub i32 %x, %sr.shl
  %r = mul i32 %x, -7
  ret i32 %r
}

; -14 = -(2^4 - 2^1) = 2^1 - 2^4
define i32 @mul_minus14(i32 %x) {
; CHECK-LABEL: define i32 @mul_minus14(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 4
; CHECK-NEXT:    %sr.shl1 = shl i32 %x, 1
; CHECK-NEXT:    %r = sub i32 %sr.shl1, %sr.shl
  %r = mul i32 -14, %x
  ret i32 %r
}

; Flags are dropped for every negative multiplier (INT_MIN is the exception,
; covered in powers_of_two.ll).
define i32 @flags_dropped_neg(i32 %x) {
; CHECK-LABEL: define i32 @flags_dropped_neg(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %r = sub i32 0, %sr.shl
  %r = mul nuw nsw i32 %x, -8
  ret i32 %r
}

define <4 x i32> @vec_mul_minus8(<4 x i32> %x) {
; CHECK-LABEL: define <4 x i32> @vec_mul_minus8(
; CHECK-NEXT:    %sr.shl = shl <4 x i32> %x, {{(<i32 3, i32 3, i32 3, i32 3>|splat \(i32 3\))}}
; CHECK-NEXT:    %r = sub <4 x i32> zeroinitializer, %sr.shl
  %r = mul <4 x i32> %x, <i32 -8, i32 -8, i32 -8, i32 -8>
  ret <4 x i32> %r
}
