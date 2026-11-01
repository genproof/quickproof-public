/* Design test 3: body-less nondet_* functions, with and without a prototype. */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	int k = nondet_in_range(0, 10);
	size_t n = nondet_size_t();
	void *v = nondet_voidp();
	unsigned char u = nondet_uchar();     /* no prototype: implicitly int nondet_uchar() */
	if (nondet_bool())
		__CPROVER_assume(n < 5);
	__CPROVER_assume(k >= 0 && k <= 10);
	(void) v;
	(void) u;
}
