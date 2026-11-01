/* afl_repro.h: the AFL++ macros of a persistent-mode harness as afl-cc defines them and as they behave outside
 * afl-fuzz (a reproduction run, `./target < FILE`), to build the original of a law of `tools/qp import-fuzz
 * --style afl` without AFL++ (`tools/qp fidelity` force-includes it with -include).  Test tooling, not part of any
 * law.  With afl-cc as ORIG_CC it does nothing (afl-cc defines __AFL_COMPILER).
 *
 * Outside afl-fuzz, AFL++ (afl-cc's -D__AFL_FUZZ_TESTCASE_LEN, afl-compiler-rt.o.c's __afl_persistent_loop)
 * reads the test case from standard input into a static buffer of 1 MiB each time __AFL_FUZZ_TESTCASE_LEN is
 * evaluated, and __AFL_LOOP is true once. */
#ifndef __AFL_COMPILER
#include <unistd.h>
#define __AFL_COMPILER 1
#define __AFL_HAVE_MANUAL_CONTROL 1
static unsigned char qp_afl_repro_buf[1 << 20];
static unsigned int qp_afl_repro_len;
static unsigned int qp_afl_repro_loops;
#define __AFL_FUZZ_INIT() extern unsigned int qp_afl_repro_unused
#define __AFL_INIT() ((void) 0)
#define __AFL_FUZZ_TESTCASE_BUF qp_afl_repro_buf
#define __AFL_FUZZ_TESTCASE_LEN \
	((qp_afl_repro_len = (unsigned int) read(0, qp_afl_repro_buf, 1 << 20)) == 0xffffffff ? 0 : qp_afl_repro_len)
#define __AFL_LOOP(n) (qp_afl_repro_loops++ == 0)
#define __AFL_COVERAGE() extern unsigned int qp_afl_repro_unused
#define __AFL_COVERAGE_ON() ((void) 0)
#define __AFL_COVERAGE_OFF() ((void) 0)
#define __AFL_COVERAGE_DISCARD() ((void) 0)
#define __AFL_COVERAGE_SKIP() ((void) 0)
#define __AFL_LEAK_CHECK() ((void) 0)
#endif
