/* An AFL++ persistent-mode harness of the toy library (tests/perlaw/lib), for tests/qp/fuzz_engines.sh, in the form
 * of AFL++'s instrumentation/README.persistent_mode.md: the fallback macros for builds without afl-cc, setup code
 * before the loop, the buffer read once before the loop, `continue` on short inputs.  Byte 0 is the bound of a
 * fresh counter, byte 1 the number of increments; the count must be min(byte 1, byte 0).  A first byte 0xff ends
 * the process (exit is not a crash for AFL++). */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../lib/counter.h"

#ifndef __AFL_FUZZ_TESTCASE_LEN
ssize_t fuzz_len;
#define __AFL_FUZZ_TESTCASE_LEN fuzz_len
unsigned char fuzz_buf[1024000];
#define __AFL_FUZZ_TESTCASE_BUF fuzz_buf
#define __AFL_FUZZ_INIT() void sync(void);
#define __AFL_LOOP(x) ((fuzz_len = read(0, fuzz_buf, sizeof(fuzz_buf))) > 0 ? 1 : 0)
#define __AFL_INIT() sync()
#endif

__AFL_FUZZ_INIT();

static struct counter total;           /* state kept across the inputs of one process */

int main(void)
{
	unsigned char *buf;
	total.n = 0;
	total.max = 1000000;
	__AFL_INIT();
	buf = __AFL_FUZZ_TESTCASE_BUF;
	while (__AFL_LOOP(10000)) {
		int len = __AFL_FUZZ_TESTCASE_LEN;
		struct counter c;
		unsigned i, want;
		if (len < 2)
			continue;
		if (buf[0] == 0xff)
			exit(1);
		c.n = 0;
		c.max = buf[0];
		for (i = 0; i < buf[1]; i++)
			counter_inc(&c);
		want = buf[1] < buf[0] ? buf[1] : buf[0];
		if (counter_get(&c) != want)
			abort();
		counter_inc(&total);
	}
	return 0;
}
