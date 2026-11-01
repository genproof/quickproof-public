/* An AFL++ harness that reads its input itself from stdin inside the loop (tests/qp/fuzz_engines.sh): refused by
 * import-fuzz --style afl, which has no model of stdin yet. */
#include <stdlib.h>
#include <unistd.h>
#include "../lib/counter.h"

int main(void)
{
	unsigned char buf[64];
	while (__AFL_LOOP(1000)) {
		ssize_t n = read(0, buf, sizeof buf);
		struct counter c;
		if (n < 1)
			continue;
		c.n = 0;
		c.max = buf[0];
		counter_inc(&c);
	}
	return 0;
}
