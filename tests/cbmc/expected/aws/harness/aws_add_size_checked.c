/* Law imported from the CBMC proof harness `aws/verification/cbmc/proofs/aws_add_size_checked` (entry
 * aws_add_size_checked_harness) by tools/qp import-cbmc. Every execution of the harness, with every
 * uninitialised variable of the harness code and every byte of memory it allocates arbitrary (as CBMC
 * treats them), and every allocation of the harness code possibly failing (NULL), has no undefined
 * behaviour (out-of-bounds access, use after free, invalid free, null dereference, signed overflow,
 * division by zero, undefined shifts: what CBMC's default checks look for, and reads of uninitialised
 * memory in the library code, which CBMC does not flag) and passes every __CPROVER_assert,
 * __CPROVER_precondition and assert, under the harness's __CPROVER_assume. Unlike the CBMC proof, the
 * loops are not unwound to a bound: the law covers every number of iterations. Built without CBMC
 * (--undef): the checks the library makes only under CBMC are not part of the law; the harness's own
 * checks are. Not covered: termination (CBMC's unwinding assertions), the checks --unsigned-overflow-check
 * --conversion-check, which are not undefined behaviour in C. */

/* qp-import-cbmc provenance (generated; do not edit; regenerate with the command below)
 *   importer:       tools/qp import-cbmc, version 1
 *   command:        tools/qp import-cbmc aws aws/verification/cbmc/proofs/aws_add_size_checked --law aws_add_size_checked --malloc auto --undef CBMC
 *   upstream:       @UPSTREAM@
 *   commit:         61141b256e1b21805a209c98fc86e15643e85477
 *   proof:          aws/verification/cbmc/proofs/aws_add_size_checked
 *   entry:          aws_add_size_checked_harness
 *   makefile:       aws/verification/cbmc/proofs/aws_add_size_checked/Makefile sha256 35f1fcf38720bfe73f258661f1accacf0fb4d8858894f330b9c62b39c0fe9262
 *   makefile:       aws/verification/cbmc/proofs/Makefile.common sha256 3065c6d056bd3d273fce23221195eae3ba702b8887ef7c8419ffb47a117098f5
 *   makefile:       aws/verification/cbmc/proofs/Makefile-project-defines sha256 5c4ec294515cf3f3e8f64e5f61f5fa736b05843eede7ad6e22f5193f8534d8d1
 *   makefile:       aws/verification/cbmc/proofs/Makefile-template-defines sha256 19d85b2ac39b77f4add1c9ed701ce98dc63e492e0d6ad49460439bcadca66ecc
 *   source:         aws/verification/cbmc/proofs/aws_add_size_checked/aws_add_size_checked_harness.c sha256 f82b4b4cb82a54e015e7f68d8c50a8ea625ee27e90fa699ff6745dd7da2feb44 -> harness/cbmc/aws_add_size_checked/aws_add_size_checked_harness.c
 *   source:         aws/verification/cbmc/sources/make_common_data_structures.c sha256 daa4651aa5c51548ef943f681f3243c036158b345c2a209707409532cf895183 -> harness/cbmc/aws_add_size_checked/make_common_data_structures.c
 *   source:         aws/verification/cbmc/stubs/error.c sha256 0d7c37059e1388e976ed04f8d1985f5cb17dfebb248b5f36be22bf4a9028fed4 -> harness/cbmc/aws_add_size_checked/error.c
 *   source:         aws/verification/cbmc/stubs/abort_override_assert_false.c sha256 abd1334d81b1b2cdb529b0874bdc6fee5921ed0b565eba6d200bfc7ba3042fa9 -> harness/cbmc/aws_add_size_checked/abort_override_assert_false.c
 *   shim:           harness/cbmc/cbmc_env.h sha256 0dd4b52cfe68c5f980529d7cb5ce219fca79fb3aa0f57f769780f5e38b927da4
 *   options:        malloc=may-fail (auto) mem-predicates=refuse set=- undef=CBMC env=cbmc_values
 *   units:          aws/source/common.c
 *   includes:       -Iaws/verification/cbmc/include -Iaws/include
 *   defines:        -
 *   local:          -DAWS_DEEP_CHECKS=0 -DCBMC_OBJECT_BITS=8
 *                   '-DCBMC_MAX_OBJECT_SIZE=(SIZE_MAX>>(CBMC_OBJECT_BITS+1))'
 *   dropped:        unwinding assertions
 *   edits:          make_common_data_structures.c:aws_bounded_length:n=QP_CBMC_HAVOC
 *   note:           define CBMC=1 dropped (--undef)
 *   note:           REMOVE_FUNCTION_BODY abort: no body in the library code, nothing to remove (the harness code defines it)
 * The sha256 are of the upstream files at the commit; the project's PATCH, if any, applies to the library.
 * `units`, `includes` and `defines` configure the library for the whole project (the importer's block
 * of quickproof.conf); `local` are the proof's defines that only the harness code sees (below).
 * Replay protocol: the havoc sites (`edits`, FILE:FUNCTION:VARIABLE) draw in program order. */

/* The proof's defines that do not change the library code (law-local). */
#define AWS_DEEP_CHECKS 0
#define CBMC_OBJECT_BITS 8
#define CBMC_MAX_OBJECT_SIZE (SIZE_MAX>>(CBMC_OBJECT_BITS+1))
/* CBMC's uninterpreted functions and fortified builtins (see the claim). */
#define __CPROVER_uninterpreted_hasher(...) qp_cbmc_uninterpreted_hasher()
#define QP_CBMC_MALLOC QP_CBMC_MALLOC_MAY_FAIL
#include "cbmc/cbmc_env.h"

/* Declared before the harness code, defined after it (where its types are complete). */
int nondet_bool(void);
uint32_t nondet_uint32_t(void);
uint64_t nondet_uint64_t(void);

/* The harness code, rewritten only as listed above. */
#include "cbmc/aws_add_size_checked/aws_add_size_checked_harness.c"
#include "cbmc/aws_add_size_checked/make_common_data_structures.c"
#include "cbmc/aws_add_size_checked/error.c"
#include "cbmc/aws_add_size_checked/abort_override_assert_false.c"

/* The body-less nondet_* and uninterpreted functions of the harness: any value of the return type. */
int nondet_bool(void)
{
	int qp_v;
	QP_CBMC_HAVOC(qp_v);
	return qp_v;
}

uint32_t nondet_uint32_t(void)
{
	uint32_t qp_v;
	QP_CBMC_HAVOC(qp_v);
	return qp_v;
}

uint64_t nondet_uint64_t(void)
{
	uint64_t qp_v;
	QP_CBMC_HAVOC(qp_v);
	return qp_v;
}

int main(void)
{
	aws_add_size_checked_harness();
	qp_assert(1);        /* the end is reached: a marker for the non-vacuity gate (trivially true) */
	return 0;
}
