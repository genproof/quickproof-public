/* honggfuzz_env.h: the honggfuzz environment of a law imported from a honggfuzz persistent-mode harness
 * (`HF_ITER`; tools/qp import-fuzz --style honggfuzz, docs/FUZZ-IMPORT.md).
 *
 * Copied into projects/NAME/harness/fuzz/ by `tools/qp import-fuzz` (with a provenance line); edit the original
 * in the framework's tools/fuzz/, never the copy.  The law includes it after libfuzzer_env.h (crashes,
 * allocation, output) and before the harness, whose own `main` the law calls.
 *
 * It adds nothing to the trusted base: plain C on top of quickproof.h, compiled into the law and verified with
 * it.  It defines what libhfuzz provides, with the meaning it has in one honggfuzz process:
 *
 *   HF_ITER(&buf, &len), HonggfuzzFetchData(&buf, &len)
 *       the first call: a fresh buffer of exactly len nondet bytes (honggfuzz hands out a pointer per call,
 *       so the buffer can be exact, as in the libFuzzer import); the next call ends the run without error
 *       (QP_HF_STATEFUL 0), or gives the next input, up to QP_HF_STATEFUL inputs, at a nondet choice (-1: any
 *       number).  The previous buffer is released first: honggfuzz reuses it.
 *   exit(s), _Exit(s)
 *       the end of the run, not a crash (honggfuzz reports signals: abort(), a failing assert(), sanitizer
 *       reports); the law asserts no leak first with QP_FUZZ_LEAKS.
 *
 * The harness declares HF_ITER itself, with `const uint8_t **` or `uint8_t **`: QP_HF_ITER_CONST (set by the
 * importer from that declaration) gives the definition the same type.  QP_HF_MAX_LEN bounds the length
 * (--max-len).
 *
 * Replay protocol (tools/qp replay): nondet_size() is the length of the next input, nondet_bytes its bytes,
 * nondet_u8() is 1 when another input follows (stateful laws).
 */
#ifndef QP_HONGGFUZZ_ENV_H
#define QP_HONGGFUZZ_ENV_H

#ifndef QP_HF_STATEFUL
#define QP_HF_STATEFUL 0
#endif
#ifndef QP_HF_ITER_CONST
#define QP_HF_ITER_CONST 1
#endif

/* ---- the end of a run ---------------------------------------------------------------------------- */

/* The run ends without error.  In the theorem nothing after it is considered (gp_assume(0)); native runs and
 * replays leave the process with status 0, which is what honggfuzz sees. */
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

/* ---- the inputs ------------------------------------------------------------------------------------ */

unsigned int qp_hf_inputs;               /* inputs handed out */
uint8_t *qp_hf_data;                     /* the current input */

void qp_hf_next(const uint8_t **buf, size_t *len)
{
	size_t n;
	if (qp_hf_data != NULL) {
		qp_fuzz_raw_free(qp_hf_data);
		qp_hf_data = NULL;
	}
	if (qp_hf_inputs > 0) {
#if QP_HF_STATEFUL == 0
		qp_fuzz_end();
#else
#if QP_HF_STATEFUL > 0
		if (qp_hf_inputs == QP_HF_STATEFUL)
			qp_fuzz_end();
#endif
		if (nondet_u8() == 0)
			qp_fuzz_end();
#endif
	}
	n = nondet_size();
#ifdef QP_HF_MAX_LEN
	gp_assume(n <= QP_HF_MAX_LEN);
#endif
	qp_hf_data = qp_fuzz_raw_malloc(n);
	gp_assume(qp_hf_data != NULL);
	nondet_bytes(qp_hf_data, n);
	qp_hf_inputs = qp_hf_inputs + 1;
	*buf = qp_hf_data;
	*len = n;
}

#if QP_HF_ITER_CONST
void HF_ITER(const uint8_t **buf, size_t *len)
{
	qp_hf_next(buf, len);
}

void HonggfuzzFetchData(const uint8_t **buf, size_t *len)
{
	qp_hf_next(buf, len);
}
#else
void HF_ITER(uint8_t **buf, size_t *len)
{
	qp_hf_next((const uint8_t **) buf, len);
}

void HonggfuzzFetchData(uint8_t **buf, size_t *len)
{
	qp_hf_next((const uint8_t **) buf, len);
}
#endif

#endif /* QP_HONGGFUZZ_ENV_H */
