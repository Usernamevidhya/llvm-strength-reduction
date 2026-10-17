; mul by 2^a + 2^b or 2^a - 2^b  ->  shift + add/sub
; RUN: %sr_opt -passes=strength-reduce -S %s | FileCheck %s

define i32 @mul3(i32 %x) {
; CHECK-LABEL: define i32 @mul3(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 1
; CHECK-NEXT:    %r = add i32 %sr.shl, %x
  %r = mul i32 %x, 3
  ret i32 %r
}

define i32 @mul9(i32 %x) {
; CHECK-LABEL: define i32 @mul9(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %r = add i32 %sr.shl, %x
  %r = mul i32 %x, 9
  ret i32 %r
}

define i32 @mul10(i32 %x) {
; CHECK-LABEL: define i32 @mul10(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %sr.shl1 = shl i32 %x, 1
; CHECK-NEXT:    %r = add i32 %sr.shl, %sr.shl1
  %r = mul i32 %x, 10
  ret i32 %r
}

define i32 @mul12_constant_lhs(i32 %x) {
; CHECK-LABEL: define i32 @mul12_constant_lhs(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %sr.shl1 = shl i32 %x, 2
; CHECK-NEXT:    %r = add i32 %sr.shl, %sr.shl1
  %r = mul i32 12, %x
  ret i32 %r
}

; 2^a - 2^b forms
define i32 @mul7(i32 %x) {
; CHECK-LABEL: define i32 @mul7(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %r = sub i32 %sr.shl, %x
  %r = mul i32 %x, 7
  ret i32 %r
}

define i32 @mul15(i32 %x) {
; CHECK-LABEL: define i32 @mul15(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 4
; CHECK-NEXT:    %r = sub i32 %sr.shl, %x
  %r = mul i32 %x, 15
  ret i32 %r
}

define i32 @mul14(i32 %x) {
; CHECK-LABEL: define i32 @mul14(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 4
; CHECK-NEXT:    %sr.shl1 = shl i32 %x, 1
; CHECK-NEXT:    %r = sub i32 %sr.shl, %sr.shl1
  %r = mul i32 %x, 14
  ret i32 %r
}

define i64 @mul_i64(i64 %x) {
; CHECK-LABEL: define i64 @mul_i64(
; CHECK-NEXT:    %sr.shl = shl i64 %x, 33
; CHECK-NEXT:    %r = add i64 %sr.shl, %x
  %r = mul i64 %x, 8589934593
  ret i64 %r
}

; Flags: for 2^a + 2^b > 0 every partial result is bounded by the final one,
; so nuw/nsw are valid on all new instructions.
define i32 @flags_add_form(i32 %x) {
; CHECK-LABEL: define i32 @flags_add_form(
; CHECK-NEXT:    %sr.shl = shl nuw nsw i32 %x, 3
; CHECK-NEXT:    %r = add nuw nsw i32 %sr.shl, %x
  %r = mul nuw nsw i32 %x, 9
  ret i32 %r
}

; For 2^a - 2^b the intermediate (x << a) can wrap even if x*C does not, so
; all flags must be dropped.
define i32 @flags_sub_form_dropped(i32 %x) {
; CHECK-LABEL: define i32 @flags_sub_form_dropped(
; CHECK-NEXT:    %sr.shl = shl i32 %x, 3
; CHECK-NEXT:    %r = sub i32 %sr.shl, %x
  %r = mul nuw nsw i32 %x, 7
  ret i32 %r
}

define <4 x i32> @vec_mul9(<4 x i32> %x) {
; CHECK-LABEL: define <4 x i32> @vec_mul9(
; CHECK-NEXT:    %sr.shl = shl <4 x i32> %x, {{(<i32 3, i32 3, i32 3, i32 3>|splat \(i32 3\))}}
; CHECK-NEXT:    %r = add <4 x i32> %sr.shl, %x
  %r = mul <4 x i32> %x, <i32 9, i32 9, i32 9, i32 9>
  ret <4 x i32> %r
}
