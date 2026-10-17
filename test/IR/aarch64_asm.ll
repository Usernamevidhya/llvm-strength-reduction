; Static assembly comparison with llc -mtriple=aarch64 at -O0 (where the backend
; does not strength-reduce on its own): before the pass a multiply needs a
; constant materialisation plus `mul`; after it, only shifts / add / sub.
;
; REQUIRES: aarch64-registered-target
; RUN: llc -mtriple=aarch64 -O0 %s -o - | FileCheck %s --check-prefix=BEFORE
; RUN: %sr_opt -passes=strength-reduce -S %s | llc -mtriple=aarch64 -O0 -o - | FileCheck %s --check-prefix=AFTER

define i32 @mul8(i32 %x) {
  %r = mul i32 %x, 8
  ret i32 %r
}

define i32 @mul9(i32 %x) {
  %r = mul i32 %x, 9
  ret i32 %r
}

define i32 @mul_minus7(i32 %x) {
  %r = mul i32 %x, -7
  ret i32 %r
}

; (FastISel already lowers power-of-two multiplies to `lsl` at -O0, so mul8 is
; not checked "before"; it is the composite and negative constants that gain.)
; BEFORE-LABEL: mul9:
; BEFORE:         mov w{{[0-9]+}}, #9
; BEFORE-NEXT:    mul w0, w0, w{{[0-9]+}}
; BEFORE-LABEL: mul_minus7:
; BEFORE:         mul w0, w0, w{{[0-9]+}}

; AFTER-LABEL: mul8:
; AFTER-NOT:     {{[[:space:]]mul[[:space:]]}}
; AFTER:         lsl w0, w0, #3
; AFTER-LABEL: mul9:
; AFTER-NOT:     {{[[:space:]]mul[[:space:]]}}
; AFTER:         add w0, w0, w0, lsl #3
; AFTER-LABEL: mul_minus7:
; AFTER-NOT:     {{[[:space:]]mul[[:space:]]}}
; AFTER:         sub{{s?}} w0, w0, w0, lsl #3
