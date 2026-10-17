; mul by 2^k  ->  shl k   (constant on either side, scalar and vector)
; RUN: %sr_opt -passes=strength-reduce -S %s | FileCheck %s

define i32 @mul8(i32 %x) {
; CHECK-LABEL: define i32 @mul8(
; CHECK-NEXT:    %r = shl i32 %x, 3
; CHECK-NEXT:    ret i32 %r
  %r = mul i32 %x, 8
  ret i32 %r
}

define i32 @mul2_constant_lhs(i32 %x) {
; CHECK-LABEL: define i32 @mul2_constant_lhs(
; CHECK-NEXT:    %r = shl i32 %x, 1
  %r = mul i32 2, %x
  ret i32 %r
}

define i64 @mul1024_i64(i64 %x) {
; CHECK-LABEL: define i64 @mul1024_i64(
; CHECK-NEXT:    %r = shl i64 %x, 10
  %r = mul i64 %x, 1024
  ret i64 %r
}

define i8 @mul64_i8(i8 %x) {
; CHECK-LABEL: define i8 @mul64_i8(
; CHECK-NEXT:    %r = shl i8 %x, 6
  %r = mul i8 %x, 64
  ret i8 %r
}

; Overflow flags carry over to a single shl.
define i32 @flags_nuw_nsw(i32 %x) {
; CHECK-LABEL: define i32 @flags_nuw_nsw(
; CHECK-NEXT:    %r = shl nuw nsw i32 %x, 4
  %r = mul nuw nsw i32 %x, 16
  ret i32 %r
}

define i32 @flags_nuw_only(i32 %x) {
; CHECK-LABEL: define i32 @flags_nuw_only(
; CHECK-NEXT:    %r = shl nuw i32 %x, 4
  %r = mul nuw i32 %x, 16
  ret i32 %r
}

; INT_MIN is 2^31 as a bit pattern.  nuw is still exact, but nsw must be
; dropped: `shl nsw i32 1, 31` is poison while `mul nsw i32 1, INT_MIN` is not.
define i32 @int_min_nsw_dropped(i32 %x) {
; CHECK-LABEL: define i32 @int_min_nsw_dropped(
; CHECK-NEXT:    %r = shl i32 %x, 31
  %r = mul nsw i32 %x, -2147483648
  ret i32 %r
}

define i32 @int_min_nuw_kept(i32 %x) {
; CHECK-LABEL: define i32 @int_min_nuw_kept(
; CHECK-NEXT:    %r = shl nuw i32 %x, 31
  %r = mul nuw i32 %x, -2147483648
  ret i32 %r
}

; Splat vector constants.
define <4 x i32> @vec_mul8(<4 x i32> %x) {
; CHECK-LABEL: define <4 x i32> @vec_mul8(
; CHECK-NEXT:    %r = shl <4 x i32> %x, {{(<i32 3, i32 3, i32 3, i32 3>|splat \(i32 3\))}}
  %r = mul <4 x i32> %x, <i32 8, i32 8, i32 8, i32 8>
  ret <4 x i32> %r
}

; All uses are rewritten and the original mul is gone.
define i32 @multiple_uses(i32 %x) {
; CHECK-LABEL: define i32 @multiple_uses(
; CHECK-NOT:     mul
; CHECK:         %m = shl i32 %x, 2
; CHECK-NEXT:    %a = add i32 %m, 1
; CHECK-NEXT:    %b = xor i32 %m, %a
; CHECK-NEXT:    ret i32 %b
  %m = mul i32 %x, 4
  %a = add i32 %m, 1
  %b = xor i32 %m, %a
  ret i32 %b
}
