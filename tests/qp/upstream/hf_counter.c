/* A honggfuzz persistent-mode harness of the toy library (tests/perlaw/lib), for tests/qp/fuzz_engines.sh, in the
 * form of honggfuzz's docs/PersistentFuzzing.md (HF_ITER declared by the harness, an endless loop).  The same
 * check as afl_counter.c; the last byte is read through the exact-size buffer. */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "../lib/counter.h"

extern void HF_ITER(uint8_t **buf, size_t *len);

int main(void)
{
	for (;;) {
		size_t len;
		uint8_t *buf;
		struct counter c;
		unsigned i, want;
		HF_ITER(&buf, &len);
		if (len < 2)
			continue;
		c.n = 0;
		c.max = buf[0];
		for (i = 0; i < buf[1]; i++)
			counter_inc(&c);
		want = buf[1] < buf[0] ? buf[1] : buf[0];
		if (counter_get(&c) != want || buf[len - 1] == 0xfe)
			abort();
	}
}
