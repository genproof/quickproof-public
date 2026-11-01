/* A libFuzzer target of the toy library (tests/perlaw/lib), for tests/qp/e2e.sh: the first input byte is the
 * bound of a fresh counter; one increment must succeed exactly when the bound is not 0. */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "../lib/counter.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct counter c;
	c.n = 0;
	c.max = size > 0 ? data[0] : 0;
	if (counter_inc(&c) != (c.max != 0))
		abort();
	if (counter_get(&c) != (c.max != 0))
		abort();
	return 0;
}
