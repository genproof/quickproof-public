/* Design test 2: allocation in harness code. */
#include <stdlib.h>
#include "toy_cbmc.h"

void harness(void)
{
	size_t n;
	__CPROVER_assume(n <= 16);
	uint8_t *raw = malloc(n);
	struct toy_buf *b = malloc(sizeof(struct toy_buf));
	struct toy_buf *bs = malloc(sizeof(struct toy_buf) * 2);
	struct toy_buf *z = calloc(1, sizeof(struct toy_buf));
	bool *flag = malloc(sizeof(bool));
	char **pp = malloc(sizeof(char *));
	struct toy_buf *viaexpr = malloc(sizeof(*viaexpr));
	if (b != NULL) {
		b->data = raw;
		__CPROVER_assume(b->cap <= n && b->len <= b->cap);
		toy_buf_push(b, 7);
	}
	if (flag != NULL)
		__CPROVER_assert(*flag == 0 || *flag == 1, "a _Bool cell is 0 or 1");
	if (z != NULL)
		__CPROVER_assert(z->len == 0, "calloc zeroes");
	(void) bs;
	(void) pp;
	(void) viaexpr;
}
