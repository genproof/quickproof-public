/* Law imported from the CBMC proof harness `mqtt/test/cbmc/proofs/MQTT_MatchTopic` (entry harness) by
 * tools/qp import-cbmc. Every execution of the harness, with every uninitialised variable of the harness
 * code and every byte of memory it allocates arbitrary (as CBMC treats them), and every allocation of the
 * harness code possibly failing (NULL), has no undefined behaviour (out-of-bounds access, use after free,
 * invalid free, null dereference, signed overflow, division by zero, undefined shifts: what CBMC's default
 * checks look for, and reads of uninitialised memory in the library code, which CBMC does not flag) and
 * passes every __CPROVER_assert, __CPROVER_precondition and assert, under the harness's __CPROVER_assume.
 * Unlike the CBMC proof, the loops are not unwound to a bound: the law covers every number of iterations.
 * The harness's own bounds (the defines of its Makefile) stay: MAX_TOPIC_NAME_FILTER_LENGTH=10. Not
 * covered: termination (CBMC's unwinding assertions), the checks --unsigned-overflow-check
 * --conversion-check, which are not undefined behaviour in C. */

/* qp-import-cbmc provenance (generated; do not edit; regenerate with the command below)
 *   importer:       tools/qp import-cbmc, version 1
 *   command:        tools/qp import-cbmc mqtt mqtt/test/cbmc/proofs/MQTT_MatchTopic --law MQTT_MatchTopic --malloc auto
 *   upstream:       @UPSTREAM@
 *   commit:         61141b256e1b21805a209c98fc86e15643e85477
 *   proof:          mqtt/test/cbmc/proofs/MQTT_MatchTopic
 *   entry:          harness
 *   makefile:       mqtt/test/cbmc/proofs/MQTT_MatchTopic/Makefile sha256 6a167927fee24f423215499a6f810050b54ff0ba96d0ff50f951a8a01f7273a3
 *   makefile:       mqtt/test/cbmc/proofs/Makefile.common sha256 06e373e9baa52b66d637c22a8282dba340e00d6c5f12c45939319c75745d27ae
 *   makefile:       mqtt/test/cbmc/proofs/Makefile-project-defines sha256 125d0769dc5a15a33ba891aa2a97d8bded904e3a5e8cf183d40ba59d56d450a1
 *   makefile:       mqtt/test/cbmc/proofs/Makefile-template-defines sha256 514ad466125407330200e275f3a93013ebc9d3197889d12aaa658bc40975d2ec
 *   source:         mqtt/test/cbmc/proofs/MQTT_MatchTopic/MQTT_MatchTopic_harness.c sha256 6c85a31d1bb3131fa90ba5d34cb9380f7545cc3e5706f04ef8d5138786bf931b -> harness/cbmc/MQTT_MatchTopic/MQTT_MatchTopic_harness.c
 *   source:         mqtt/test/cbmc/sources/mqtt_cbmc_state.c sha256 62f360c2bf6bacdd61dad713dd259c1540f6aacd0c41dc78d5ed02e8d50d0e54 -> harness/cbmc/MQTT_MatchTopic/mqtt_cbmc_state.c
 *   shim:           harness/cbmc/cbmc_env.h sha256 0dd4b52cfe68c5f980529d7cb5ce219fca79fb3aa0f57f769780f5e38b927da4
 *   options:        malloc=may-fail (auto) mem-predicates=refuse set=- undef=- env=cbmc_values
 *   units:          mqtt/source/core_mqtt.c
 *   includes:       -Imqtt/test/cbmc/include -Imqtt/source/include -Imqtt/source/src
 *                   -Imqtt/source/interface
 *   defines:        -
 *   local:          -DMAX_TOPIC_NAME_FILTER_LENGTH=10 -Dmqtt_EXPORTS
 *   dropped:        UNWINDSET __CPROVER_file_local_core_mqtt_c_matchTopicFilter.0:10 strncmp.0:10 __CPROVER_file_local_core_mqtt_c_matchWildcards.0:10;
 *                   unwinding assertions
 *   edits:          MQTT_MatchTopic_harness.c:harness:pTopicName=QP_CBMC_HAVOC_PTR
 *                   MQTT_MatchTopic_harness.c:harness:nameLength=QP_CBMC_HAVOC
 *                   MQTT_MatchTopic_harness.c:harness:pTopicFilter=QP_CBMC_HAVOC_PTR
 *                   MQTT_MatchTopic_harness.c:harness:filterLength=QP_CBMC_HAVOC
 *                   MQTT_MatchTopic_harness.c:harness:pMatchResult=QP_CBMC_HAVOC_PTR
 *                   MQTT_MatchTopic_harness.c: malloc(sizeof(bool)) -> qp_cbmc_malloc_scalar_bool()
 *                   mqtt_cbmc_state.c:isValidMqttTopic:ok=QP_CBMC_HAVOC_BOOL
 *   note:           include directory -Imqtt/source/src is not in the tree
 *   note:           include directory -Imqtt/source/interface is not in the tree
 * The sha256 are of the upstream files at the commit; the project's PATCH, if any, applies to the library.
 * `units`, `includes` and `defines` configure the library for the whole project (the importer's block
 * of quickproof.conf); `local` are the proof's defines that only the harness code sees (below).
 * Replay protocol: the havoc sites (`edits`, FILE:FUNCTION:VARIABLE) draw in program order. */

/* The proof's defines that do not change the library code (law-local). */
#define MAX_TOPIC_NAME_FILTER_LENGTH 10
#define mqtt_EXPORTS 1
#define QP_CBMC_MALLOC QP_CBMC_MALLOC_MAY_FAIL
#include "cbmc/cbmc_env.h"

/* The harness code, rewritten only as listed above. */
#include "cbmc/MQTT_MatchTopic/MQTT_MatchTopic_harness.c"
#include "cbmc/MQTT_MatchTopic/mqtt_cbmc_state.c"

int main(void)
{
	harness();
	qp_assert(1);        /* the end is reached: a marker for the non-vacuity gate (trivially true) */
	return 0;
}
