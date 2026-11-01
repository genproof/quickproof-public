/* HARNESS_ENTRY names a function that the harness code does not define: refused. */
#include "toy_cbmc.h"

void harness(void)
{
	int x;
	(void) toy_twice(x);
}
