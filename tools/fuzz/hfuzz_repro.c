/* hfuzz_repro.c: libhfuzz's HF_ITER and HonggfuzzFetchData for a reproduction run (`./target < FILE`), to build
 * the original of a law of `tools/qp import-fuzz --style honggfuzz` without honggfuzz (`tools/qp fidelity` links
 * it).  Test tooling, not part of any law.  The first call returns the whole standard input in a buffer of
 * exactly its length; the next call ends the process with status 0, as the end of a honggfuzz run is not a
 * crash. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int calls;

void HF_ITER(const uint8_t **buf, size_t *len)
{
	size_t cap = 4096, n = 0;
	ssize_t r;
	unsigned char *b = malloc(cap), *exact;
	if (calls++ > 0)
		exit(0);
	while (b && (r = read(0, b + n, cap - n)) > 0) {
		n += (size_t) r;
		if (n == cap)
			b = realloc(b, cap *= 2);
	}
	if (!b) {
		fprintf(stderr, "hfuzz_repro: out of memory\n");
		_exit(4);
	}
	exact = malloc(n);              /* exactly n bytes, so that an overread is a sanitizer report */
	if (!exact && n) {
		fprintf(stderr, "hfuzz_repro: out of memory\n");
		_exit(4);
	}
	if (n)
		memcpy(exact, b, n);
	free(b);
	*buf = exact;
	*len = n;
}

void HonggfuzzFetchData(const uint8_t **buf, size_t *len)
{
	HF_ITER(buf, len);
}
