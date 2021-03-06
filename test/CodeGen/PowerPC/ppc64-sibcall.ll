; RUN: llc < %s -O1 -disable-ppc-sco=false -verify-machineinstrs -mtriple=powerpc64-unknown-linux-gnu | FileCheck %s -check-prefix=CHECK-SCO
; RUN: llc < %s -O1 -disable-ppc-sco=false -verify-machineinstrs -mtriple=powerpc64-unknown-linux-gnu -mcpu=pwr8 | FileCheck %s -check-prefix=CHECK-SCO-HASQPX
; RUN: llc < %s -O1 -disable-ppc-sco=false -verify-machineinstrs -mtriple=powerpc64le-unknown-linux-gnu -mcpu=pwr8 | FileCheck %s -check-prefix=CHECK-SCO-HASQPX

; No combination of "powerpc64le-unknown-linux-gnu" + "CHECK-SCO", because
; only Power8 (and later) fully support LE.

%S_56 = type { [13 x i32], i32 }
%S_64 = type { [15 x i32], i32 }
%S_32 = type { [7 x i32], i32 }

; Function Attrs: noinline nounwind
define void @callee_56_copy([7 x i64] %a, %S_56* %b) #0 { ret void }
define void @callee_64_copy([8 x i64] %a, %S_64* %b) #0 { ret void }

; Function Attrs: nounwind
define void @caller_56_reorder_copy(%S_56* %b, [7 x i64] %a) #1 {
  tail call void @callee_56_copy([7 x i64] %a, %S_56* %b)
  ret void

; CHECK-SCO-LABEL: caller_56_reorder_copy:
; CHECK-SCO-NOT: stdu 1
; CHECK-SCO: TC_RETURNd8 callee_56_copy
}

define void @caller_64_reorder_copy(%S_64* %b, [8 x i64] %a) #1 {
  tail call void @callee_64_copy([8 x i64] %a, %S_64* %b)
  ret void

; CHECK-SCO-LABEL: caller_64_reorder_copy:
; CHECK-SCO: bl callee_64_copy
}

define void @callee_64_64_copy([8 x i64] %a, [8 x i64] %b) #0 { ret void }
define void @caller_64_64_copy([8 x i64] %a, [8 x i64] %b) #1 {
  tail call void @callee_64_64_copy([8 x i64] %a, [8 x i64] %b)
  ret void

; CHECK-SCO-LABEL: caller_64_64_copy:
; CHECK-SCO: b callee_64_64_copy
}

define void @caller_64_64_reorder_copy([8 x i64] %a, [8 x i64] %b) #1 {
  tail call void @callee_64_64_copy([8 x i64] %b, [8 x i64] %a)
  ret void

; CHECK-SCO-LABEL: caller_64_64_reorder_copy:
; CHECK-SCO: bl callee_64_64_copy
}

define void @caller_64_64_undef_copy([8 x i64] %a, [8 x i64] %b) #1 {
  tail call void @callee_64_64_copy([8 x i64] %a, [8 x i64] undef)
  ret void

; CHECK-SCO-LABEL: caller_64_64_undef_copy:
; CHECK-SCO: b callee_64_64_copy
}

define void @arg8_callee(
  float %a, i32 signext %b, float %c, i32* %d,
  i8 zeroext %e, float %f, i32* %g, i32 signext %h)
{
  ret void
}

define void @arg8_caller(float %a, i32 signext %b, i8 zeroext %c, i32* %d) {
entry:
  tail call void @arg8_callee(float undef, i32 signext undef, float undef,
                              i32* %d, i8 zeroext undef, float undef,
                              i32* undef, i32 signext undef)
  ret void

; CHECK-SCO-LABEL: arg8_caller:
; CHECK-SCO: b arg8_callee
}

; Struct return test

; Function Attrs: noinline nounwind
define void @callee_sret_56(%S_56* noalias sret %agg.result) #0 { ret void }
define void @callee_sret_32(%S_32* noalias sret %agg.result) #0 { ret void }

; Function Attrs: nounwind
define void @caller_do_something_sret_32(%S_32* noalias sret %agg.result) #1 {
  %1 = alloca %S_56, align 4
  %2 = bitcast %S_56* %1 to i8*
  call void @callee_sret_56(%S_56* nonnull sret %1)
  tail call void @callee_sret_32(%S_32* sret %agg.result)
  ret void

; CHECK-SCO-LABEL: caller_do_something_sret_32:
; CHECK-SCO: stdu 1
; CHECK-SCO: bl callee_sret_56
; CHECK-SCO: addi 1
; CHECK-SCO: TC_RETURNd8 callee_sret_32
}

define void @caller_local_sret_32(%S_32* %a) #1 {
  %tmp = alloca %S_32, align 4
  tail call void @callee_sret_32(%S_32* nonnull sret %tmp)
  ret void

; CHECK-SCO-LABEL: caller_local_sret_32:
; CHECK-SCO: bl callee_sret_32
}

attributes #0 = { noinline nounwind  }
attributes #1 = { nounwind }

; vector <4 x i1> test

define void @callee_v4i1(i8 %a, <4 x i1> %b, <4 x i1> %c) { ret void }
define void @caller_v4i1_reorder(i8 %a, <4 x i1> %b, <4 x i1> %c) {
  tail call void @callee_v4i1(i8 %a, <4 x i1> %c, <4 x i1> %b)
  ret void

; <4 x i1> is 32 bytes aligned, if subtarget doesn't support qpx, then we can't
; place b, c to qpx register, so we can't do sco on caller_v4i1_reorder

; CHECK-SCO-LABEL: caller_v4i1_reorder:
; CHECK-SCO: bl callee_v4i1

; CHECK-SCO-HASQPX-LABEL: caller_v4i1_reorder:
; CHECK-SCO-HASQPX: b callee_v4i1
}

define void @f128_callee(i32* %ptr, ppc_fp128 %a, ppc_fp128 %b) { ret void }
define void @f128_caller(i32* %ptr, ppc_fp128 %a, ppc_fp128 %b) {
  tail call void @f128_callee(i32* %ptr, ppc_fp128 %a, ppc_fp128 %b)
  ret void

; CHECK-SCO-LABEL: f128_caller:
; CHECK-SCO: b f128_callee
}

; weak linkage test
%class.T = type { [2 x i8] }

define weak_odr hidden void @wo_hcallee(%class.T* %this, i8* %c) { ret void }
define void @wo_hcaller(%class.T* %this, i8* %c) {
  tail call void @wo_hcallee(%class.T* %this, i8* %c)
  ret void

; CHECK-SCO-LABEL: wo_hcaller:
; CHECK-SCO: b wo_hcallee
}

define weak_odr protected void @wo_pcallee(%class.T* %this, i8* %c) { ret void }
define void @wo_pcaller(%class.T* %this, i8* %c) {
  tail call void @wo_pcallee(%class.T* %this, i8* %c)
  ret void

; CHECK-SCO-LABEL: wo_pcaller:
; CHECK-SCO: b wo_pcallee
}

define weak_odr void @wo_callee(%class.T* %this, i8* %c) { ret void }
define void @wo_caller(%class.T* %this, i8* %c) {
  tail call void @wo_callee(%class.T* %this, i8* %c)
  ret void

; CHECK-SCO-LABEL: wo_caller:
; CHECK-SCO: bl wo_callee
}

define weak protected void @w_pcallee(i8* %ptr) { ret void }
define void @w_pcaller(i8* %ptr) {
  tail call void @w_pcallee(i8* %ptr)
  ret void

; CHECK-SCO-LABEL: w_pcaller:
; CHECK-SCO: b w_pcallee
}

define weak hidden void @w_hcallee(i8* %ptr) { ret void }
define void @w_hcaller(i8* %ptr) {
  tail call void @w_hcallee(i8* %ptr)
  ret void

; CHECK-SCO-LABEL: w_hcaller:
; CHECK-SCO: b w_hcallee
}

define weak void @w_callee(i8* %ptr) { ret void }
define void @w_caller(i8* %ptr) {
  tail call void @w_callee(i8* %ptr)
  ret void

; CHECK-SCO-LABEL: w_caller:
; CHECK-SCO: bl w_callee
}
