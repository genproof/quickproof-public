/* Pointer provenance in harness code: refused. */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	uint8_t *a = malloc(4);
	uint8_t *b = malloc(4);
	__CPROVER_assume(__CPROVER_POINTER_OBJECT(a) != __CPROVER_POINTER_OBJECT(b));
}
