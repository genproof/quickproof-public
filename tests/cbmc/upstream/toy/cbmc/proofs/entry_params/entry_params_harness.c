/* An entry function with parameters: main gives them arbitrary values. */
#include <stdlib.h>
#include "toy_cbmc.h"
#include "local.h"

void harness(size_t n, struct toy_buf *b, bool flag)
{
	__CPROVER_assume(n <= LOCAL_MAX);
	if (b != NULL && flag)
		toy_buf_push(b, (uint8_t) n);
}
