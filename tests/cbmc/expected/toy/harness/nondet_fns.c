/* Law imported from the CBMC proof harness `toy/cbmc/proofs/nondet_fns` (entry harness) by tools/qp
 * import-cbmc. Every execution of the harness, with every uninitialised variable of the harness code and
 * every byte of memory it allocates arbitrary (as CBMC treats them), and every allocation of the harness
 * code possibly failing (NULL), has no undefined behaviour (out-of-bounds access, use after free, invalid
 * free, null dereference, signed overflow, division by zero, undefined shifts: what CBMC's default checks
 * look for, and reads of uninitialised memory in the library code, which CBMC does not flag) and passes
 * every __CPROVER_assert, __CPROVER_precondition and assert, under the harness's __CPROVER_assume. Unlike
 * the CBMC proof, the loops are not unwound to a bound: the law covers every number of iterations. Not
 * covered: termination (CBMC's unwinding assertions), the checks --unsigned-overflow-check
 * --conversion-check --pointer-overflow-check, which are not undefined behaviour in C. */

/* qp-import-cbmc provenance (generated; do not edit; regenerate with the command below)
 *   importer:       tools/qp import-cbmc, version 1
 *   command:        tools/qp import-cbmc toy toy/cbmc/proofs/nondet_fns --law nondet_fns --malloc auto
 *   upstream:       @UPSTREAM@
 *   commit:         61141b256e1b21805a209c98fc86e15643e85477
 *   proof:          toy/cbmc/proofs/nondet_fns
 *   entry:          harness
 *   makefile:       toy/cbmc/proofs/nondet_fns/Makefile sha256 b721fe0abd30eb09de31f8ffae5a426c7934a5202789cc3f400589a8292ed71a
 *   makefile:       toy/cbmc/proofs/Makefile.common sha256 5a4d5fcdcfde14c4a15590ccaa690abd1a847b4096d7dcd6528f18b91ef411ec
 *   makefile:       toy/cbmc/proofs/Makefile-project-defines sha256 3c3fa46dc125ce80367d794cabef56797e19c4d530b434aa144d1763ec28fa45
 *   makefile:       toy/cbmc/proofs/Makefile-template-defines sha256 f4bbb7f758173d7f48baf5f30abc54869494b7c7d7bc6779faa51a3105d036aa
 *   source:         toy/cbmc/proofs/nondet_fns/nondet_fns_harness.c sha256 63d18da24852b22842f149dc3e4da30ef98d11e19638719f61ca170eeb94e62b -> harness/cbmc/nondet_fns/nondet_fns_harness.c
 *   source:         toy/cbmc/stubs/abort_override.c sha256 617243fe179b40f8e098336ebc1f3790dc6ccbef5665001ca9696712329a7b2f -> harness/cbmc/nondet_fns/abort_override.c
 *   shim:           harness/cbmc/cbmc_env.h sha256 0dd4b52cfe68c5f980529d7cb5ce219fca79fb3aa0f57f769780f5e38b927da4
 *   options:        malloc=may-fail (auto) mem-predicates=refuse set=- undef=- env=cbmc_values
 *   units:          toy/src/toy.c
 *   includes:       -Itoy/src -Itoy/cbmc/include
 *   defines:        -DTOY_CONFIG=1
 *   local:          '-DTOY_HARNESS_ONLY=(1 + 1)' -DCBMC=1
 *   dropped:        unwinding assertions
 *   edits:          -
 *   note:           toy/cbmc/proofs/Makefile-project-defines:15: DEFINES += ... inside a conditional block: skipped (the importer does not evaluate conditionals)
 *   note:           REMOVE_FUNCTION_BODY abort: no body in the library code, nothing to remove (the harness code defines it)
 * The sha256 are of the upstream files at the commit; the project's PATCH, if any, applies to the library.
 * `units`, `includes` and `defines` configure the library for the whole project (the importer's block
 * of quickproof.conf); `local` are the proof's defines that only the harness code sees (below).
 * Replay protocol: the havoc sites (`edits`, FILE:FUNCTION:VARIABLE) draw in program order. */

/* The proof's defines that do not change the library code (law-local). */
#define TOY_HARNESS_ONLY (1 + 1)
#define CBMC 1
/* CBMC's uninterpreted functions and fortified builtins (see the claim). */
#define __CPROVER_uninterpreted_hash(...) qp_cbmc_uninterpreted_hash()
#define QP_CBMC_MALLOC QP_CBMC_MALLOC_MAY_FAIL
#include "cbmc/cbmc_env.h"

/* Declared before the harness code, defined after it (where its types are complete). */
bool nondet_bool(void);
int nondet_in_range(int qp_a0, int qp_a1);
size_t nondet_size_t(void);
int nondet_uchar(void);
void *nondet_voidp(void);

/* The harness code, rewritten only as listed above. */
#include "cbmc/nondet_fns/nondet_fns_harness.c"
#include "cbmc/nondet_fns/abort_override.c"

/* The body-less nondet_* and uninterpreted functions of the harness: any value of the return type. */
bool nondet_bool(void)
{
	bool qp_v;
	QP_CBMC_HAVOC_BOOL(qp_v);
	return qp_v;
}

int nondet_in_range(int qp_a0, int qp_a1)
{
	(void) qp_a0;
	(void) qp_a1;
	int qp_v;
	QP_CBMC_HAVOC(qp_v);
	return qp_v;
}

size_t nondet_size_t(void)
{
	size_t qp_v;
	QP_CBMC_HAVOC(qp_v);
	return qp_v;
}

int nondet_uchar(void)
{
	int qp_v;
	QP_CBMC_HAVOC(qp_v);
	return qp_v;
}

void *nondet_voidp(void)
{
	void *qp_v;
	QP_CBMC_HAVOC_PTR(qp_v);
	return qp_v;
}

int main(void)
{
	harness();
	qp_assert(1);        /* the end is reached: a marker for the non-vacuity gate (trivially true) */
	return 0;
}
