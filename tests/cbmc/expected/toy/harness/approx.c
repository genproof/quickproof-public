/* Law imported from the CBMC proof harness `toy/cbmc/proofs/approx` (entry harness) by tools/qp
 * import-cbmc. Every execution of the harness, with every uninitialised variable of the harness code and
 * every byte of memory it allocates arbitrary (as CBMC treats them), and every allocation of the harness
 * code possibly failing (NULL), has no undefined behaviour (out-of-bounds access, use after free, invalid
 * free, null dereference, signed overflow, division by zero, undefined shifts: what CBMC's default checks
 * look for, and reads of uninitialised memory in the library code, which CBMC does not flag) and passes
 * every __CPROVER_assert, __CPROVER_precondition and assert, under the harness's __CPROVER_assume. Unlike
 * the CBMC proof, the loops are not unwound to a bound: the law covers every number of iterations. CBMC's
 * pointer-validity predicates (__CPROVER_r_ok, __CPROVER_w_ok) are replaced by true: in 1 assertion(s) the
 * law checks the accesses that follow instead (weaker than CBMC if the harness does not access that
 * memory); in 1 assumption(s) the assumption is dropped (the law covers more executions). Not covered:
 * termination (CBMC's unwinding assertions), the checks --unsigned-overflow-check --conversion-check
 * --pointer-overflow-check, which are not undefined behaviour in C. */

/* qp-import-cbmc provenance (generated; do not edit; regenerate with the command below)
 *   importer:       tools/qp import-cbmc, version 1
 *   command:        tools/qp import-cbmc toy toy/cbmc/proofs/approx --law approx --malloc auto --approx-mem-predicates
 *   upstream:       @UPSTREAM@
 *   commit:         61141b256e1b21805a209c98fc86e15643e85477
 *   proof:          toy/cbmc/proofs/approx
 *   entry:          harness
 *   makefile:       toy/cbmc/proofs/approx/Makefile sha256 da10efdd27340fcc644c8df505791ae7dcd38d23383c97fa0e9e4a32147b52d2
 *   makefile:       toy/cbmc/proofs/Makefile.common sha256 5a4d5fcdcfde14c4a15590ccaa690abd1a847b4096d7dcd6528f18b91ef411ec
 *   makefile:       toy/cbmc/proofs/Makefile-project-defines sha256 3c3fa46dc125ce80367d794cabef56797e19c4d530b434aa144d1763ec28fa45
 *   makefile:       toy/cbmc/proofs/Makefile-template-defines sha256 f4bbb7f758173d7f48baf5f30abc54869494b7c7d7bc6779faa51a3105d036aa
 *   source:         toy/cbmc/stubs/fill_stub.c sha256 6bcccace49325e33a01a144674ee191c52a46e900956987220eb62d272fa2150 -> harness/cbmc/approx/fill_stub.c
 *   source:         toy/cbmc/proofs/approx/approx_harness.c sha256 5932fcf2da31bed8e380b91396f575d4cb22f99c10004e1817c4288028288048 -> harness/cbmc/approx/approx_harness.c
 *   source:         toy/cbmc/stubs/abort_override.c sha256 617243fe179b40f8e098336ebc1f3790dc6ccbef5665001ca9696712329a7b2f -> harness/cbmc/approx/abort_override.c
 *   shim:           harness/cbmc/cbmc_env.h sha256 0dd4b52cfe68c5f980529d7cb5ce219fca79fb3aa0f57f769780f5e38b927da4
 *   options:        malloc=may-fail (auto) mem-predicates=approx set=- undef=- env=cbmc_values
 *   units:          toy/src/toy.c
 *   includes:       -Itoy/src -Itoy/cbmc/include
 *   defines:        -DTOY_CONFIG=1
 *   local:          '-DTOY_HARNESS_ONLY=(1 + 1)' -DCBMC=1
 *   dropped:        unwinding assertions
 *   edits:          approx_harness.c:harness:n=QP_CBMC_HAVOC
 *   warning:        called through a declaration without a prototype (CompCert's semantics makes such a call undefined: the law fails there until the harness code declares a prototype): __CPROVER_r_ok, __CPROVER_w_ok
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
#define QP_CBMC_APPROX_MEM_PREDICATES 1
#include "cbmc/cbmc_env.h"

/* The harness code, rewritten only as listed above. */
#include "cbmc/approx/fill_stub.c"
#include "cbmc/approx/approx_harness.c"
#include "cbmc/approx/abort_override.c"

int main(void)
{
	harness();
	qp_assert(1);        /* the end is reached: a marker for the non-vacuity gate (trivially true) */
	return 0;
}
