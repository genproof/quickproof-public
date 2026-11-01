/* make_common_data_structures.h: a stand-in for aws-c-common's proof helper header, written for the tests of
 * tools/qp import-cbmc (it is not aws-c-common's code). */
#ifndef MAKE_COMMON_DATA_STRUCTURES_H
#define MAKE_COMMON_DATA_STRUCTURES_H
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

/* The nondet functions of proof_helpers/nondet.h, without bodies (nondet_bool is declared in no header:
 * the harness calls it without a prototype, as CBMC allows). */
uint32_t nondet_uint32_t(void);
uint64_t nondet_uint64_t(void);

/* Inconsistent declarations of one uninterpreted function, as in aws-c-common's proof helpers. */
uint64_t __CPROVER_uninterpreted_hasher(void *a);
#endif
