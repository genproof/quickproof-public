/* A fuzz target in OpenSSL's style (fuzz/NAME.c: FuzzerInitialize, FuzzerTestOneInput, FuzzerCleanup, called by
 * fuzz/driver.c), for tests/qp/fuzz_engines.sh: the initialisation allocates a block that only the cleanup frees,
 * so the law's leak check holds only if the cleanup runs first. */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "../lib/counter.h"

static struct counter *shared;

int FuzzerInitialize(int *argc, char ***argv)
{
	(void) argc;
	(void) argv;
	shared = malloc(sizeof *shared);
	if (shared == NULL)
		abort();
	shared->n = 0;
	shared->max = 1000;
	return 1;
}

int FuzzerTestOneInput(const uint8_t *buf, size_t len)
{
	struct counter c;
	c.n = 0;
	c.max = len > 0 ? buf[0] : 0;
	if (counter_inc(&c) != (c.max != 0))
		abort();
	(void) counter_inc(shared);
	return 0;
}

void FuzzerCleanup(void)
{
	free(shared);
	shared = NULL;
}
