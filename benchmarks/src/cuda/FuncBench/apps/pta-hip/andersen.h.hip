/*

  Copyright (c) 2012 The University of Texas at Austin

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
  USA, or see <http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>.

  Author: Mario Mendez-Lojo
*/

#ifndef ANDERSEN_H
#define ANDERSEN_H

#include <assert.h>
#include <hip/hip_runtime.h>
#include <hip/hip_runtime.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>


// production or debug mode
// in debug mode, only one warp is active in the whole grid.
#define DEBUG 0
#define CHECK_SPV 0
#define PRINT_RULES 0

// Amount of memory reserved for the graph edges. It has to be slightly smaller
// than the total amount of memory available in the system
#define HEAP_SIZE_MB (3930)

typedef unsigned int uint;
typedef unsigned long int ulongint;
#define uintSize (sizeof(uint))

#define BASE_OF(x) ((x) / ELEMENT_CARDINALITY)
#define WORD_OF(x) (div32((x) % ELEMENT_CARDINALITY))
#define BIT_OF(x) (mod32(x))

#define WARPS_PER_BLOCK(x) (x / WARP_SIZE)
#define WARPS(x) (x / WARP_SIZE * BLOCKS)

#define I2P (1U)
#define NIL (UINT_MAX)
// offset for the given field of an element
#define BASE (30U)
#define NEXT (31U)

#define PTS 0
#define NEXT_DIFF_PTS 1
#define CURR_DIFF_PTS 2
#define COPY_INV 3
#define LOAD_INV 4
#define STORE 5
#define GEP_INV 7
#define LAST_DYNAMIC_REL STORE

// size (in words) of an element
#define ELEMENT_WIDTH 32
#define ELEMENT_CARDINALITY (30 * 32)

#define HEAP_SIZE_MBf ((float) HEAP_SIZE_MB)
// Size of the region dedicated to CURR_DIFF_PTS edges
#define CURR__DIFF_PTS_REGION_SIZE_MB ((uint) (HEAP_SIZE_MBf * 0.1425))
// Size of the region dedicated to copy/load/store edges
#define OTHER_REGION_SIZE_MB ((uint) (HEAP_SIZE_MBf * 0.1475))
// sizes are given in 32-bit words
#define HEAP_SIZE (HEAP_SIZE_MB * 1024 * 256) 
#define MAX_HASH_SIZE (1 << 20)
#define COPY_INV_START (HEAP_SIZE - OTHER_REGION_SIZE_MB * 1024 * 256)  // COPY region  
#define CURR_DIFF_PTS_START (COPY_INV_START - ELEMENT_WIDTH)
#define NEXT_DIFF_PTS_START (CURR_DIFF_PTS_START - CURR__DIFF_PTS_REGION_SIZE_MB * 1024 * 256 - ELEMENT_WIDTH)     

// profiling variables. No need to set them up for your system unless your are timing device
// invocations
#define CLOCK_FREQUENCY (1500000.0f) // 1.15M cycles per ms for Quadro 6000/ Tesla C2070
#define TICKS_TO_MS(x) (((double)(x)) / CLOCK_FREQUENCY)
// bytes to megabytes

#define B2MB(x) ((x)/(1024 * 1024))
// megabytes to bytes
#define MB2B(x) ((x) * 1024 * 1024)

#define MAX_NODES (1 << 22)
#define OFFSET_BITS 10
#define MAX_GEP_OFFSET (1 << OFFSET_BITS)
#define OFFSET_MASK (MAX_GEP_OFFSET - 1)
// all 1's except for bits 30 and 31
#define LT_BASE ((1 << 30) - 1)
// all 1's except for bit 31
#define LT_NEXT ((((uint)(1 << 31)) - 1))

// given in words
#define DECODE_VECTOR_SIZE (128) // has to be power of two

// maximum size of an HCD table
#define HCD_TABLE_SIZE (256)
#define HCD_DECODE_VECTOR_SIZE (8192) // maxed out for 'pine' input

#define PRINT_BUFFER_SIZE (16384) // up to this many neighbors
#define ERROR_MESSAGE_BUFFER_SIZE (512)

#define WARP_SIZE warpSize
#define LOG2_32 5

#define MAX_WARPS_PER_BLOCK (16)

// number of threads per block for each rule. The thread count is based on the amount of shared
// memory available and empirical measures.
//#define DEF_THREADS_PER_BLOCK (1024)
//#define UPDATE_THREADS_PER_BLOCK (1024)
//#define HCD_THREADS_PER_BLOCK (512)
//#define COPY_INV_THREADS_PER_BLOCK (864)
//#define STORE_INV_THREADS_PER_BLOCK (864)
//#define GEP_INV_THREADS_PER_BLOCK (1024)

#define DEF_THREADS_PER_BLOCK (1024)
#define UPDATE_THREADS_PER_BLOCK (1024)
#define HCD_THREADS_PER_BLOCK (512)
#define COPY_INV_THREADS_PER_BLOCK (512)
#define STORE_INV_THREADS_PER_BLOCK (512)
#define GEP_INV_THREADS_PER_BLOCK (512)

#define UNLOCKED (UINT_MAX)
#define LOCKED (UINT_MAX - 1)
#define VAR(x) (((x) + (UINT_MAX >> 1)))
#define PTR(x) ((x)) 

#define cudaSafeCall(err) { \
  if (hipSuccess != err) { \
    fprintf(stderr, "%s(%i) : Runtime API error %d : %s.\n",__FILE__, __LINE__, (int) err, hipGetErrorString(err));\
    exit(-1); \
  }\
}

#define D2H hipMemcpyDeviceToHost
#define H2D hipMemcpyHostToDevice

extern "C" void createGraph(const uint numObjectVars, const uint maxOffset);
extern "C" uint andersen(uint numVars);


 __host__ INLINE uint getBlocks() {
   if (DEBUG) {
     return 1;
   }
  hipDeviceProp_t deviceProp;
  hipGetDeviceProperties(&deviceProp, 0);
  return deviceProp.multiProcessorCount;	
}

 __host__ INLINE uint getThreadsPerBlock(uint intended) {
     return DEBUG ? WARP_SIZE : intended;
 }
 
//////////// utility functions used in both the CPU and GPU /////////

__device__ __host__ INLINE const char* getName(uint rel) {
  if (rel == PTS) return "PTS";
  if (rel == NEXT_DIFF_PTS) return "NEXT_DIFF_PTS";
  if (rel == CURR_DIFF_PTS) return "CURR_DIFF_PTS";
  if (rel == COPY_INV) return "COPY_INV";
  if (rel == LOAD_INV) return "LOAD_INV";
  if (rel == STORE) return "STORE";
  if (rel == GEP_INV) return "GEP_INV";
  return "UNKNOWN_REL";
}

// ellapsed time, in milliseconds
__device__ __host__ INLINE uint getEllapsedTime(const clock_t& startTime) {
  //TODO: this code should depend on whether it is executing on the GPU or the CPU
  return (int) (1000.0f * (clock() - startTime) / CLOCKS_PER_SEC);
}

__device__ __host__ static INLINE int isBitActive(uint word, uint bit) {
  return word & (1 << bit);
}

__device__ __host__ static INLINE uint isOdd(uint num) {
  return num & 1;
}

__device__ __host__ static INLINE uint mul32(uint num) {
  return num << LOG2_32;
}

__device__ __host__ static INLINE uint div32(uint num) {
  return num >> LOG2_32;
}

__device__ __host__ static INLINE uint mod32(uint num) {
  return num & 31;
}

// base has to be a power of two
__device__ __host__ static INLINE uint mod(uint num, uint base) {
  return num & (base - 1);
}

__device__ __host__ static INLINE uint getFirst(uint pair) {
  return pair >> 16;
}

__device__ __host__ static INLINE uint getSecond(uint pair) {
  return (pair & 0x0000FFFF);
}

__device__ __host__ static INLINE uint createPair(uint first, uint second) {
  return (first << 16) | second;
}

// related to GEP constraints
__device__ __host__ static INLINE uint offset(const uint srcOffset) {
  return srcOffset & OFFSET_MASK;
}

// related to GEP constraints
__device__ __host__ static INLINE uint id(const uint srcOffset) {
  return srcOffset >> OFFSET_BITS;
}

__device__ __host__ static INLINE uint idOffset(const uint src, const uint offset) {
  return offset | (src << OFFSET_BITS);
}

// e.g. for powerOfTwo==32: 4 => 32, 32 => 32, 33 => 64
// second parameter has to be a power of two
__device__ __host__ static INLINE uint roundToNextMultipleOf(uint num, uint powerOfTwo) {
  if ((num & (powerOfTwo - 1)) == 0) {
    return num;
  }
  return (num / powerOfTwo + 1) * powerOfTwo;
}

// e.g. for powerOfTwo==32: 0 => 0, 4 => 0, 32 => 32, 33 => 32
// second parameter has to be a power of two
__device__ __host__ static INLINE uint roundToPrevMultipleOf(uint num, uint powerOfTwo) {
  if ((num & (powerOfTwo - 1)) == 0) {
    return num;
  }
  return ((num / powerOfTwo + 1) * powerOfTwo) - 32;
}

// The second parameter has to be a power of 2
__device__ __host__ static INLINE int isMultipleOf(uint num, uint powerOfTwo) {
  return !(num & (powerOfTwo - 1));
}
#endif
