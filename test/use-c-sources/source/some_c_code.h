#ifndef SOME_C_CODE_H
#define SOME_C_CODE_H

#include <stdint.h>
#include <stddef.h>

extern void relatedCode(size_t aNumber);
extern uint64_t multiplyU64byU32(uint64_t*a, uint32_t*b);
extern uint64_t multiplyAndAdd(uint32_t*arr, size_t arrlen, uint32_t mult);
extern uint64_t fac(uint64_t n);

#endif