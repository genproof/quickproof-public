/* --nondet-static: refused in version 1. */
#include "toy_cbmc.h"

void harness(void)
{
	int x;
	(void) toy_twice(x);
}
