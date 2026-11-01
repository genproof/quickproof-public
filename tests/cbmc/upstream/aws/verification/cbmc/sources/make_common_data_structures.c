/* make_common_data_structures.c: a stand-in for aws-c-common's proof helpers, written for the tests of tools/qp
 * import-cbmc (it is not aws-c-common's code). */
#include <proof_helpers/make_common_data_structures.h>

uint64_t __CPROVER_uninterpreted_hasher(const void *const a, size_t n);

size_t aws_bounded_length(size_t max)
{
	size_t n;
	__CPROVER_assume(n <= max);
	return n;
}
