/* Pointer-validity predicates in an assertion (fill_stub.c) and in an assumption (here). */
#include <stdlib.h>
#include "toy_cbmc.h"

int32_t toy_fill(void *buf, size_t n);

void harness(void)
{
	size_t n;
	__CPROVER_assume(n <= 8);
	uint8_t *buf = malloc(n);
	__CPROVER_assume(buf != NULL && __CPROVER_r_ok(buf, n));
	(void) toy_fill(buf, n);
}
