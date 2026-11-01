/* afl_env.h: the AFL++ environment of a law imported from an AFL++ persistent-mode harness
 * (tools/qp import-fuzz --style afl, docs/FUZZ-IMPORT.md).
 *
 * Copied into projects/NAME/harness/fuzz/ by `tools/qp import-fuzz` (with a provenance line); edit the original
 * in the framework's tools/fuzz/, never the copy.  The law includes it after libfuzzer_env.h (crashes, allocation,
 * output) and before the harness, whose own `main` the law calls.
 *
 * It adds nothing to the trusted base: plain C on top of quickproof.h, compiled into the law and verified with
 * it.  It defines the macros that afl-cc would define, with the meaning they have in one AFL++ process:
 *
 *   __AFL_FUZZ_INIT(), __AFL_INIT(), __AFL_COVERAGE*, __AFL_LEAK_CHECK()   nothing to do;
 *   __AFL_HAVE_MANUAL_CONTROL, __AFL_COMPILER                             defined, so the AFL++ side of a
 *                                                                         harness is compiled;
 *   __AFL_FUZZ_TESTCASE_BUF   one buffer of QP_AFL_MAX bytes for the whole run (AFL++'s test case buffer; 1 MiB
 *                             by default), zeroed once: beyond the input it holds zeros or the bytes of earlier
 *                             inputs, as AFL++'s buffer does in a reproduction run;
 *   __AFL_FUZZ_TESTCASE_LEN   the length of the current input;
 *   __AFL_LOOP(N)             true for the first input, then false (QP_AFL_STATEFUL 0: one input, as in a
 *                             reproduction run), or true again for up to QP_AFL_STATEFUL inputs (and at most N),
 *                             at a nondet choice (-1: any number).  Each input is a nondet length n <=
 *                             QP_AFL_MAX and n nondet bytes at the start of the buffer.  A harness that reads
 *                             __AFL_FUZZ_TESTCASE_LEN before any __AFL_LOOP (deferred mode only) gets its
 *                             input then.
 *   exit(s), _Exit(s)         the end of the run, not a crash (AFL++ reports signals: abort(), a failing
 *                             assert(), sanitizer reports); the law asserts no leak first with QP_FUZZ_LEAKS.
 *
 * Replay protocol (tools/qp replay): nondet_size() is the length of the next input, nondet_bytes its bytes,
 * nondet_u8() is 1 when another input follows (stateful laws).
 */
#ifndef QP_AFL_ENV_H
#define QP_AFL_ENV_H

#ifndef QP_AFL_MAX
#define QP_AFL_MAX ((size_t) 1 << 20)
#endif
#ifndef QP_AFL_STATEFUL
#define QP_AFL_STATEFUL 0
#endif

/* ---- the end of a run ---------------------------------------------------------------------------- */

/* The run ends without error.  In the theorem nothing after it is considered (gp_assume(0)); native runs and
 * replays leave the process with status 0, which is what AFL++ sees. */
void qp_fuzz_end(void)
{
#if QP_FUZZ_LEAKS
	gp_assert(qp_fuzz_live == 0);       /* every block the harness allocated is freed */
#endif
#ifndef __COMPCERT__
	(exit)(0);
#endif
	gp_assume(0);
	for (;;) {
	}
}

void qp_fuzz_end_status(int status)
{
	(void) status;
	qp_fuzz_end();
}

#undef exit
#undef _Exit
#define exit(status) qp_fuzz_end_status(status)
#define _Exit(status) qp_fuzz_end_status(status)

/* ---- the test case --------------------------------------------------------------------------------- */

unsigned char *qp_afl_buf;
unsigned int qp_afl_len;
unsigned int qp_afl_inputs;              /* inputs drawn */
unsigned int qp_afl_loops;               /* calls of __AFL_LOOP that returned true */

/* The buffer, once, before the harness runs (called by the law's main). */
void qp_afl_setup(void)
{
	qp_afl_buf = qp_fuzz_raw_malloc(QP_AFL_MAX);
	gp_assume(qp_afl_buf != NULL);
	memset(qp_afl_buf, 0, QP_AFL_MAX);
}

void qp_afl_draw(void)
{
	size_t n = nondet_size();
	gp_assume(n <= QP_AFL_MAX);
	nondet_bytes(qp_afl_buf, n);
	qp_afl_len = (unsigned int) n;
	qp_afl_inputs = qp_afl_inputs + 1;
}

unsigned int qp_afl_testcase_len(void)
{
	if (qp_afl_inputs == 0)
		qp_afl_draw();
	return qp_afl_len;
}

int qp_afl_loop(unsigned int max)
{
	if (qp_afl_loops == 0) {
		qp_afl_loops = 1;
		if (qp_afl_inputs == 0)
			qp_afl_draw();
		return 1;
	}
#if QP_AFL_STATEFUL == 0
	(void) max;
	return 0;
#else
#if QP_AFL_STATEFUL > 0
	if (qp_afl_loops == QP_AFL_STATEFUL)
		return 0;
#endif
	if (max != 0 && qp_afl_loops >= max)
		return 0;                       /* AFL++ starts a new process after N inputs */
	if (nondet_u8() == 0)
		return 0;
	qp_afl_loops = qp_afl_loops + 1;
	qp_afl_draw();
	return 1;
#endif
}

#undef __AFL_COMPILER
#undef __AFL_HAVE_MANUAL_CONTROL
#define __AFL_COMPILER 1
#define __AFL_HAVE_MANUAL_CONTROL 1
#define __AFL_FUZZ_INIT() extern unsigned int qp_afl_len
#define __AFL_INIT() ((void) 0)
#define __AFL_FUZZ_TESTCASE_BUF qp_afl_buf
#define __AFL_FUZZ_TESTCASE_LEN qp_afl_testcase_len()
#define __AFL_LOOP(n) qp_afl_loop(n)
#define __AFL_COVERAGE() extern unsigned int qp_afl_len
#define __AFL_COVERAGE_ON() ((void) 0)
#define __AFL_COVERAGE_OFF() ((void) 0)
#define __AFL_COVERAGE_DISCARD() ((void) 0)
#define __AFL_COVERAGE_SKIP() ((void) 0)
#define __AFL_LEAK_CHECK() ((void) 0)

#endif /* QP_AFL_ENV_H */
