/* Design test 4: an uninterpreted function with two inconsistent declarations (toy_cbmc.h, toy_state.c). */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	struct toy_buf *b = toy_alloc_buf(8);
	uint64_t h = __CPROVER_uninterpreted_hash(b);
	(void) h;
}
