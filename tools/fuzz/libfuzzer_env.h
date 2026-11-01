/* libfuzzer_env.h: the libFuzzer environment of a law imported from a fuzz target (tools/qp import-fuzz).
 *
 * Copied into projects/NAME/harness/fuzz/ by `tools/qp import-fuzz` (with a provenance line); edit the
 * original in the framework's tools/fuzz/, never the copy.
 *
 * It adds nothing to the trusted base.  Every function here is plain C on top of quickproof.h (gp_assert,
 * gp_assume) and the framework's malloc/free; it is compiled into the law and verified with it.  Its job
 * is to make every event that libFuzzer reports as a crash a failing gp_assert, i.e. undefined
 * behaviour, which harness_safe excludes:
 *
 *   abort(), exit(), _Exit()      a failing check of the target (FUZZ_ASSERT-style macros end in abort)
 *                                 or an exit during the run ("fuzz target exited");
 *   a failing assert()            glibc's assert calls __assert_fail, defined here; it serves every unit,
 *                                 the library's too (e.g. lz4 with LZ4_DEBUG=1);
 *   malloc of LIMIT bytes or more libFuzzer's -malloc_limit_mb (default: its -rss_limit_mb, 2048 MiB)
 *                                 ("out-of-memory (malloc(N))"), policy QP_FUZZ_ALLOC_LIMIT;
 *   calloc whose size overflows   ASan's calloc-overflow report;
 *   a block not freed by the end  LeakSanitizer (QP_FUZZ_LEAKS; stronger than LSan, see docs/FUZZ-IMPORT.md).
 *
 * Memory errors and undefined behaviour (what ASan and UBSan report) need no mapping: they are undefined
 * behaviour in CompCert's semantics or fail VST's type checks (signed overflow), so harness_safe excludes
 * them directly.
 *
 * Allocation success.  Under libFuzzer with ASan, malloc never returns NULL: a request either succeeds or
 * the run is reported (malloc limit, ASan's allocation-size-too-big, RSS limit).  The framework's malloc
 * (VST's malloc_spec') may return NULL on any call, so the law states the fuzzer's behaviour as an
 * explicit assumption, gp_assume(p != NULL) after each allocation of the target (policies LIMIT and
 * ASSUME).  Policy MAYFAIL keeps the framework's semantics: the target must cope with NULL.
 *
 * Output (printf, fprintf, puts, fputs, fputc, putc, putchar, fflush, perror, fwrite) is dropped: libFuzzer
 * does not look at it.  The calls are replaced by a function returning 0 (fwrite: its count argument), and
 * their arguments are not evaluated.
 *
 * Configuration (macros defined by the law before it includes this file):
 *   QP_FUZZ_ALLOC         QP_FUZZ_ALLOC_LIMIT (default), QP_FUZZ_ALLOC_ASSUME or QP_FUZZ_ALLOC_MAYFAIL
 *   QP_FUZZ_MALLOC_LIMIT  the limit in bytes (policy LIMIT), e.g. ((size_t) 2048 << 20)
 *   QP_FUZZ_LEAKS         1: count live blocks (qp_fuzz_live), the law asserts 0 at its end
 *
 * Every name defined here starts with qp_fuzz_, except the C library's abort/exit/__assert_fail entry
 * points, which are macros (abort, exit, _Exit) or the glibc function (__assert_fail).
 */
#ifndef QP_LIBFUZZER_ENV_H
#define QP_LIBFUZZER_ENV_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include "quickproof.h"

#define QP_FUZZ_ALLOC_LIMIT   1
#define QP_FUZZ_ALLOC_ASSUME  2
#define QP_FUZZ_ALLOC_MAYFAIL 3
#ifndef QP_FUZZ_ALLOC
#define QP_FUZZ_ALLOC QP_FUZZ_ALLOC_LIMIT
#endif
#ifndef QP_FUZZ_MALLOC_LIMIT
#define QP_FUZZ_MALLOC_LIMIT ((size_t) 2048 << 20)
#endif
#ifndef QP_FUZZ_LEAKS
#define QP_FUZZ_LEAKS 0
#endif

/* ---- crashes ---------------------------------------------------------------------------------- */

/* What libFuzzer reports as a crash.  gp_assert(0) never returns (its precondition is false); the loop
 * only keeps the function from returning in C terms (abort and exit must not return). */
void qp_fuzz_crash(void)
{
	gp_assert(0);
	for (;;) {
	}
}

void qp_fuzz_abort(void)
{
	qp_fuzz_crash();
}

void qp_fuzz_exit(int status)
{
	(void) status;
	qp_fuzz_crash();
}

/* glibc's assert(e) expands to __assert_fail(#e, __FILE__, __LINE__, __func__) when e is false.  Defined
 * here (not a macro) so that the library units' assertions reach it too. */
void __assert_fail(const char *assertion, const char *file, unsigned int line, const char *function)
{
	(void) assertion;
	(void) file;
	(void) line;
	(void) function;
	qp_fuzz_crash();
}

#undef abort
#undef exit
#undef _Exit
#define abort() qp_fuzz_abort()
#define exit(status) qp_fuzz_exit(status)
#define _Exit(status) qp_fuzz_exit(status)

/* ---- allocation ------------------------------------------------------------------------------- */

/* Live blocks of the target (QP_FUZZ_LEAKS); the law sets it to 0 first and asserts 0 at its end. */
size_t qp_fuzz_live;

/* The framework's allocator, for the law's own buffers (the input): not counted, no policy.  In the
 * theorem `malloc` is quickproof_malloc (tools/clight.sh renames it), in native runs the C library's. */
void *qp_fuzz_raw_malloc(size_t n)
{
	return malloc(n);
}

void qp_fuzz_raw_free(void *p)
{
	free(p);
}

/* The target's malloc. */
void *qp_fuzz_malloc(size_t n)
{
#if QP_FUZZ_ALLOC == QP_FUZZ_ALLOC_LIMIT
	if (n >= QP_FUZZ_MALLOC_LIMIT)
		qp_fuzz_crash();        /* libFuzzer: out-of-memory (malloc(n)) */
#endif
	void *p = malloc(n);
#if QP_FUZZ_ALLOC != QP_FUZZ_ALLOC_MAYFAIL
	gp_assume(p != NULL);       /* under libFuzzer + ASan, malloc does not return NULL */
#endif
#if QP_FUZZ_LEAKS
	if (p != NULL)
		qp_fuzz_live = qp_fuzz_live + 1;
#endif
	return p;
}

/* The target's calloc: an overflowing size is ASan's calloc-overflow report (policy MAYFAIL: NULL, as the
 * C library returns). */
void *qp_fuzz_calloc(size_t nmemb, size_t size)
{
	if (size != 0 && nmemb > SIZE_MAX / size) {
#if QP_FUZZ_ALLOC == QP_FUZZ_ALLOC_MAYFAIL
		return NULL;
#else
		qp_fuzz_crash();        /* ASan: calloc-overflow */
#endif
	}
	unsigned char *p = qp_fuzz_malloc(nmemb * size);
	if (p != NULL)
		memset(p, 0, nmemb * size);
	return p;
}

void qp_fuzz_free(void *p)
{
#if QP_FUZZ_LEAKS
	if (p != NULL)
		qp_fuzz_live = qp_fuzz_live - 1;
#endif
	free(p);
}

#undef malloc
#undef calloc
#undef free
#define malloc qp_fuzz_malloc
#define calloc qp_fuzz_calloc
#define free qp_fuzz_free

/* ---- output ----------------------------------------------------------------------------------- */

int qp_fuzz_output(void)
{
	return 0;
}

size_t qp_fuzz_output_n(size_t n)
{
	return n;
}

#undef printf
#undef fprintf
#undef puts
#undef fputs
#undef fputc
#undef putc
#undef putchar
#undef fflush
#undef perror
#undef fwrite
#define printf(...) qp_fuzz_output()
#define fprintf(...) qp_fuzz_output()
#define puts(s) qp_fuzz_output()
#define fputs(s, stream) qp_fuzz_output()
#define fputc(c, stream) qp_fuzz_output()
#define putc(c, stream) qp_fuzz_output()
#define putchar(c) qp_fuzz_output()
#define fflush(stream) qp_fuzz_output()
#define perror(s) ((void) qp_fuzz_output())
#define fwrite(ptr, size, n, stream) qp_fuzz_output_n(n)

/* The entry points of a libFuzzer target. */
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

#endif /* QP_LIBFUZZER_ENV_H */
