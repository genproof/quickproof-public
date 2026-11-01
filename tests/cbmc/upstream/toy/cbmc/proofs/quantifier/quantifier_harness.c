/* A quantifier in harness code: refused. */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	uint8_t *a = malloc(4);
	__CPROVER_assume(a != NULL);
	__CPROVER_assume(__CPROVER_forall { int i; (0 <= i && i < 4) ==> a[i] == 0 });
}
