/* toy_state.c: shared harness code of the toy proofs (tests/qp/cbmc.sh). */
#include <stdlib.h>
#include "toy_cbmc.h"

uint64_t __CPROVER_uninterpreted_hash(const void *p, size_t n);

struct toy_buf *toy_alloc_buf(size_t max)
{
	struct toy_buf *b = malloc(sizeof(*b));
	size_t cap;
	if (b == NULL)
		return NULL;
	__CPROVER_assume(cap <= max);
	b->data = malloc(cap);
	b->cap = cap;
	__CPROVER_assume(b->len <= cap);
	return b;
}
