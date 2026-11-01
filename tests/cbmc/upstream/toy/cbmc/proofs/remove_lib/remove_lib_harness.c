/* Design test 5: REMOVE_FUNCTION_BODY of a function the library defines (refused in version 1). */
#include "toy_cbmc.h"

void harness(void)
{
	int x;
	(void) toy_replaceable(x);
}
