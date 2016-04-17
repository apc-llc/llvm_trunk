; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc < %s -mtriple=x86_64-unknown -mattr=+sse4.2 | FileCheck %s

define <2 x i64> @test(i64 %i) nounwind  {
; CHECK-LABEL: test:
; CHECK:       # BB#0:
; CHECK-NEXT:    movd %rdi, %xmm0
; CHECK-NEXT:    retq
  %tmp10 = insertelement <2 x i64> undef, i64 %i, i32 0
  %tmp11 = insertelement <2 x i64> %tmp10, i64 0, i32 1
  ret <2 x i64> %tmp11
}
