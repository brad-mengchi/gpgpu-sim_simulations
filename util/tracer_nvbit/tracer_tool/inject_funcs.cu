/* Author1: Mahmoud Khairy, abdallm@purdue.com - 2019 */
/* Author2: Jason Shen, shen203@purdue.edu - 2019 */

#include <cstdarg>
#include <stdint.h>
#include <stdio.h>

#include "utils/utils.h"

/* for channel */
#include "utils/channel.hpp"

/* contains definition of the inst_trace_t structure */
#include "common.h"

/* Instrumentation function that we want to inject, please note the use of
 *  extern "C" __device__ __noinline__
 *    To prevent "dead"-code elimination by the compiler.
 */
extern "C" __device__ __noinline__ void instrument_inst(
    int pred, int opcode_id, int32_t vpc, bool is_mem, uint32_t reg_high,
    uint32_t reg_low, int32_t imm, int32_t width, int32_t desReg,
    int32_t srcReg1, int32_t srcReg2, int32_t srcReg3, int32_t srcReg4,
    int32_t srcReg5, int32_t srcNum, uint64_t pchannel_dev,
    uint64_t ptotal_dynamic_instr_counter,
    uint64_t preported_dynamic_instr_counter, uint64_t pstop_report) {

  const int active_mask = __ballot(1);
  const int predicate_mask = __ballot(pred);
  const int laneid = get_laneid();
  const int first_laneid = __ffs(active_mask) - 1;

  if ((*((bool *)pstop_report))) {
    if (first_laneid == laneid) {
      atomicAdd((unsigned long long *)ptotal_dynamic_instr_counter, 1);
      return;
    }
  }

  inst_trace_t ma;

  if (is_mem) {
    /* collect memory address information */
    int64_t base_addr = (((uint64_t)reg_high) << 32) | ((uint64_t)reg_low);
    uint64_t addr = base_addr + imm;
    for (int i = 0; i < 32; i++) {
      ma.addrs[i] = __shfl(addr, i);
    }
    ma.width = width;
    ma.is_mem = true;
  } else {
    ma.is_mem = false;
  }

  int4 cta = get_ctaid();
  int uniqe_threadId = threadIdx.z * blockDim.y * blockDim.x +
                       threadIdx.y * blockDim.x + threadIdx.x;
  ma.warpid_tb = uniqe_threadId / 32;

  ma.cta_id_x = cta.x;
  ma.cta_id_y = cta.y;
  ma.cta_id_z = cta.z;
  ma.warpid_sm = get_warpid();
  ma.opcode_id = opcode_id;
  ma.vpc = vpc;
  ma.GPRDst = desReg;
  ma.GPRSrcs[0] = srcReg1;
  ma.GPRSrcs[1] = srcReg2;
  ma.GPRSrcs[2] = srcReg3;
  ma.GPRSrcs[3] = srcReg4;
  ma.GPRSrcs[4] = srcReg5;
  ma.numSrcs = srcNum;
  ma.active_mask = active_mask;
  ma.predicate_mask = predicate_mask;
  ma.sm_id = get_smid();

  /* first active lane pushes information on the channel */
  if (first_laneid == laneid) {
    ChannelDev *channel_dev = (ChannelDev *)pchannel_dev;
    channel_dev->push(&ma, sizeof(inst_trace_t));
    atomicAdd((unsigned long long *)ptotal_dynamic_instr_counter, 1);
    atomicAdd((unsigned long long *)preported_dynamic_instr_counter, 1);
  }
}
