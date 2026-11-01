/* A libFuzzer target that returns 1 on inputs starting with 'R' (tests/qp/fuzz_engines.sh): libFuzzer ignores the
 * return value, honggfuzz treats it as fatal, so its law under --style honggfuzz fails on such inputs. */
#include <stdint.h>
#include <stddef.h>
#include "../lib/counter.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	struct counter c;
	c.n = 0;
	c.max = size > 1 ? data[1] : 0;
	(void) counter_inc(&c);
	if (size > 0 && data[0] == 'R')
		return 1;
	return 0;
}
