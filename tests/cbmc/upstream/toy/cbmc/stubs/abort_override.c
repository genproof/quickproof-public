/* abort_override.c: abort is a failing assertion (as in aws-c-common's proofs). */
#include <assert.h>

void abort(void)
{
	assert(0);
}
