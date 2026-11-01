/* A fuzz target in Tor's style (src/test/fuzz/fuzz_NAME.c: fuzz_init, fuzz_main, fuzz_cleanup, called by
 * fuzzing_common.c), for tests/qp/fuzz_engines.sh.  TOY_BOUND selects a variant at build time (--define). */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "../lib/counter.h"

#ifndef TOY_BOUND
#define TOY_BOUND 255
#endif

static int initialised;

static int fuzz_init(void)
{
	initialised = 1;
	return 0;
}

static int fuzz_cleanup(void)
{
	initialised = 0;
	return 0;
}

int fuzz_main(const uint8_t *data, size_t sz)
{
	struct counter c;
	if (!initialised)
		abort();
	c.n = 0;
	c.max = sz > 0 ? data[0] : 0;
	if (c.max > TOY_BOUND)
		abort();
	(void) counter_inc(&c);
	return 0;
}
