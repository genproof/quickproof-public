/* A library macro that is CBMC-only under -DCBMC: refused, unless the library is built without CBMC (--undef). */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	struct toy_buf b;
	__CPROVER_assume(b.len <= 4);
	b.data = malloc(b.len);
	__CPROVER_assume(b.data != NULL);
	__CPROVER_assert(TOY_IS_READABLE(b.data, b.len), "the buffer is readable");
}
