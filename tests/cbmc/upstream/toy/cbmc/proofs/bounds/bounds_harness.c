/* Bounds: a size bound of the Makefile (kept, or widened with --set) and an unwinding bound (dropped). */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	size_t n;
	char c;
	__CPROVER_assume(n < MAX_LEN);
	char *s = malloc(n);
	if (s != NULL)
		__CPROVER_assert(toy_count(s, n, c) <= n, "count is at most the length");
}
