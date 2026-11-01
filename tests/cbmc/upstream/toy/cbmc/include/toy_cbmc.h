/* toy_cbmc.h: the harness header of the toy proofs (tests/qp/cbmc.sh). */
#ifndef TOY_CBMC_H
#define TOY_CBMC_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "toy.h"

bool nondet_bool(void);
size_t nondet_size_t(void);
void *nondet_voidp(void);
int nondet_in_range(int lo, int hi);

/* An uninterpreted function, declared twice inconsistently (as aws-c-common's proof helpers do). */
uint64_t __CPROVER_uninterpreted_hash(const void *p);

struct toy_buf *toy_alloc_buf(size_t max);
#endif
