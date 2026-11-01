/* An arbitrary floating-point value: refused. */
#include "toy_cbmc.h"

void harness(void)
{
	double d;
	__CPROVER_assume(d > 0);
}
