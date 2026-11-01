/* A pointer-validity predicate in a condition: refused even with --approx-mem-predicates. */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	uint8_t *buf = malloc(4);
	if (__CPROVER_r_ok(buf, 4))
		buf[0] = 1;
}
