/* svcomp_env.h: the SV-COMP environment of a law imported from an SV-COMP verification task
 * (tools/qp import-svcomp, docs/SVCOMP.md).
 *
 * Copied into projects/NAME/harness/svcomp/ by `tools/qp import-svcomp` (with a provenance line); edit the
 * original in the framework's tools/svcomp/, never the copy.
 *
 * It adds nothing to the trusted base.  Every function here is plain C on top of the environment of
 * quickproof.h (nondet_*, gp_assert, gp_assume) and the framework's malloc/free; it is compiled into the
 * law and verified with it.  It gives the vocabulary of SV-COMP tasks the meaning of the SV-COMP rules:
 *
 *   __VERIFIER_nondet_T()     any value of type T (bool: 0 or 1);
 *   __VERIFIER_assume(c)      gp_assume(c != 0): only the executions where c holds are considered;
 *   __VERIFIER_nondet_memory  the bytes of an object become arbitrary (SV-COMP 2026);
 *   reach_error()             the importer puts a call of qp_svcomp_reach_error(), gp_assert(0), at the start
 *                             of the task's reach_error, whatever its body: property unreach-call is "every
 *                             gp_assert holds";
 *   __VERIFIER_error()        pre-2021 tasks: gp_assert(0);
 *   abort(), exit(s), a failing assert() (__assert_fail)
 *                             the end of the execution, NOT an error (SV-COMP: only calls of reach_error and
 *                             the memory and overflow events are errors): gp_assume(0), nothing after it is
 *                             considered (with QP_SVCOMP_LEAKS: every block is freed by then);
 *   malloc(n)                 the framework's malloc (it may return NULL; QP_SVCOMP_MALLOC_NEVER_FAILS
 *                             assumes it does not), with arbitrary contents: SV-COMP gives fresh memory
 *                             arbitrary values, where CompCert would make reading it undefined;
 *   calloc(n, s)              zeroed, NULL when n * s overflows;
 *   alloca(n)                 a block of n arbitrary bytes that never fails (SV-COMP rule) and that is not
 *                             a heap block, so that free() of it is undefined as valid-free requires: it
 *                             starts one byte into a heap block of n + 1 bytes, never freed.
 *
 * No header is included, not even quickproof.h: tasks are often preprocessed .i files that carry their
 * own copies of the C library's declarations (of another glibc version, with anonymous structs that
 * would conflict with the system's).  The environment of quickproof.h is declared here with the built-in
 * types its typedefs have on x86-64 LP64 (uint8_t = unsigned char, uint32_t = unsigned int, size_t =
 * unsigned long): the same functions, the same Clight types, the same specifications in QuickProof.Env.
 * QP_NO_SYSTEM_HEADERS tells runtime/interp_driver.c, which tools/interp.sh puts after the law in one
 * translation unit, to include no header either.
 *
 * A function the task defines itself (an assume helper called __VERIFIER_assume, its own nondet
 * function) is left to the task: the importer defines QP_SVCOMP_OWN_<name> before this file.
 *
 * An asm label of a declaration (glibc's `__asm__ ("" "__isoc99_fscanf")`), which CompCert does not accept,
 * becomes QP_SVCOMP_ASM_LABEL in the importer's copy of the task: kept for gcc, dropped for CompCert.  It only
 * renames an external function, which the theorem does not have anyway.
 *
 * Configuration (macros the law defines before it includes this file):
 *   QP_SVCOMP_MALLOC_NEVER_FAILS  1: malloc and calloc do not return NULL (gp_assume); default 0
 *   QP_SVCOMP_LEAKS               1: count live heap blocks (qp_svcomp_live) for valid-memcleanup
 *
 * Every name defined here starts with qp_svcomp_, except the SV-COMP vocabulary (__VERIFIER_*) and
 * glibc's __assert_fail.
 */
#ifndef QP_SVCOMP_ENV_H
#define QP_SVCOMP_ENV_H

#define QP_NO_SYSTEM_HEADERS 1

#ifdef __COMPCERT__
#define QP_SVCOMP_ASM_LABEL(name)
#else
#define QP_SVCOMP_ASM_LABEL(name) __asm__(name)
#endif

#ifndef QP_SVCOMP_MALLOC_NEVER_FAILS
#define QP_SVCOMP_MALLOC_NEVER_FAILS 0
#endif
#ifndef QP_SVCOMP_LEAKS
#define QP_SVCOMP_LEAKS 0
#endif

extern unsigned char nondet_u8(void);
extern unsigned int nondet_u32(void);
extern unsigned long nondet_size(void);
extern void nondet_bytes(unsigned char *buf, unsigned long n);
extern void gp_assert(int cond);
extern void gp_assume(int cond);
#define qp_assert gp_assert       /* the names to write, as in quickproof.h */
#define qp_assume gp_assume
extern void *malloc(unsigned long n);
extern void free(void *p);
#define QP_SVCOMP_NULL ((void *) 0)

/* ---- the framework's allocator, before malloc and free are renamed below ---------------------------- */

/* In the theorem `malloc` and `free` are quickproof_malloc and quickproof_free (tools/clight.sh renames
 * them); in native runs, the C library's. */
void *qp_svcomp_raw_malloc(unsigned long n)
{
	return malloc(n);
}

void qp_svcomp_raw_free(void *p)
{
	free(p);
}

/* ---- the end of an execution, errors ---------------------------------------------------------------- */

/* Live heap blocks of the task (QP_SVCOMP_LEAKS). */
unsigned long qp_svcomp_live;

/* abort() and exit(): the execution ends without error.  gp_assume(0) never returns (its postcondition
 * is false), so no later code is considered; the loop only keeps the function from returning in C terms. */
void qp_svcomp_stop(void)
{
#if QP_SVCOMP_LEAKS
	gp_assert(qp_svcomp_live == 0);      /* valid-memcleanup: the program terminates here */
#endif
	gp_assume(0);
	for (;;) {
	}
}

void qp_svcomp_abort(void)
{
	qp_svcomp_stop();
}

void qp_svcomp_exit(int status)
{
	(void) status;
	qp_svcomp_stop();
}

/* reach_error(): the importer calls this at the start of the task's reach_error. */
void qp_svcomp_reach_error(void)
{
	gp_assert(0);
	for (;;) {
	}
}

/* A failing assert() outside reach_error (glibc calls __assert_fail, which aborts): the end of the execution. */
#ifndef QP_SVCOMP_OWN___assert_fail
void __assert_fail(const char *assertion, const char *file, unsigned int line, const char *function)
{
	(void) assertion;
	(void) file;
	(void) line;
	(void) function;
	qp_svcomp_stop();
}
#endif

#ifndef QP_SVCOMP_OWN___VERIFIER_error
void __VERIFIER_error(void)
{
	gp_assert(0);
	for (;;) {
	}
}
#endif

#undef abort
#undef exit
#undef _Exit
#define abort qp_svcomp_abort
#define exit qp_svcomp_exit
#define _Exit qp_svcomp_exit

/* ---- allocation ------------------------------------------------------------------------------------ */

void *qp_svcomp_malloc(unsigned long n)
{
	unsigned char *p = qp_svcomp_raw_malloc(n);
#if QP_SVCOMP_MALLOC_NEVER_FAILS
	gp_assume(p != QP_SVCOMP_NULL);
#endif
	if (p != QP_SVCOMP_NULL) {
		if (n != 0)
			nondet_bytes(p, n);
#if QP_SVCOMP_LEAKS
		qp_svcomp_live = qp_svcomp_live + 1;
#endif
	}
	return p;
}

void *qp_svcomp_calloc(unsigned long nmemb, unsigned long size)
{
	unsigned long i;
	unsigned char *p;
	if (size != 0 && nmemb > (unsigned long) -1 / size)
		return QP_SVCOMP_NULL;
	p = qp_svcomp_malloc(nmemb * size);
	if (p != QP_SVCOMP_NULL)
		for (i = 0; i < nmemb * size; i = i + 1)
			p[i] = 0;
	return p;
}

void qp_svcomp_free(void *p)
{
#if QP_SVCOMP_LEAKS
	if (p != QP_SVCOMP_NULL)
		qp_svcomp_live = qp_svcomp_live - 1;
#endif
	qp_svcomp_raw_free(p);
}

void *qp_svcomp_alloca(unsigned long n)
{
	unsigned char *p;
	gp_assume(n < (unsigned long) -1);
	p = qp_svcomp_raw_malloc(n + 1);
	gp_assume(p != QP_SVCOMP_NULL);      /* SV-COMP: alloca does not fail */
	if (n != 0)
		nondet_bytes(p + 1, n);
	return p + 1;
}

#undef malloc
#undef calloc
#undef free
#undef alloca
#undef __builtin_alloca
#define malloc qp_svcomp_malloc
#define calloc qp_svcomp_calloc
#define free qp_svcomp_free
#define alloca qp_svcomp_alloca
#define __builtin_alloca qp_svcomp_alloca

/* ---- assumptions and nondeterministic values ---------------------------------------------------------- */

#ifndef QP_SVCOMP_OWN___VERIFIER_assume
void __VERIFIER_assume(int cond)
{
	gp_assume(cond != 0);
}
#endif

/* __VERIFIER_nondet_memory(p, n) (SV-COMP 2026): the n bytes at p become arbitrary. */
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_memory
void __VERIFIER_nondet_memory(void *p, unsigned long n)
{
	if (n != 0)
		nondet_bytes((unsigned char *) p, n);
}
#endif

/* Each value is the conversion of one draw of nondet_u8, nondet_u32 or nondet_size to the type: the
 * conversion reaches every value of the type (modulo 2^N, as CompCert and gcc define it), and native
 * runs get the drivers' value shapes (small, near the top, anything). */
#define QP_SVCOMP_NONDET(T, NAME, DRAW) \
	T NAME(void) { return (T) DRAW(); }

#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_char
QP_SVCOMP_NONDET(char, __VERIFIER_nondet_char, nondet_u8)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_uchar
QP_SVCOMP_NONDET(unsigned char, __VERIFIER_nondet_uchar, nondet_u8)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_short
QP_SVCOMP_NONDET(short, __VERIFIER_nondet_short, nondet_u32)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_ushort
QP_SVCOMP_NONDET(unsigned short, __VERIFIER_nondet_ushort, nondet_u32)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_int
QP_SVCOMP_NONDET(int, __VERIFIER_nondet_int, nondet_u32)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_uint
QP_SVCOMP_NONDET(unsigned int, __VERIFIER_nondet_uint, nondet_u32)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_unsigned
QP_SVCOMP_NONDET(unsigned int, __VERIFIER_nondet_unsigned, nondet_u32)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_u32
QP_SVCOMP_NONDET(unsigned int, __VERIFIER_nondet_u32, nondet_u32)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_long
QP_SVCOMP_NONDET(long, __VERIFIER_nondet_long, nondet_size)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_ulong
QP_SVCOMP_NONDET(unsigned long, __VERIFIER_nondet_ulong, nondet_size)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_longlong
QP_SVCOMP_NONDET(long long, __VERIFIER_nondet_longlong, nondet_size)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_ulonglong
QP_SVCOMP_NONDET(unsigned long long, __VERIFIER_nondet_ulonglong, nondet_size)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_size_t
QP_SVCOMP_NONDET(unsigned long, __VERIFIER_nondet_size_t, nondet_size)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_loff_t
QP_SVCOMP_NONDET(long long, __VERIFIER_nondet_loff_t, nondet_size)
#endif
#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_sector_t
QP_SVCOMP_NONDET(unsigned long, __VERIFIER_nondet_sector_t, nondet_size)
#endif

#ifndef QP_SVCOMP_OWN___VERIFIER_nondet_bool
_Bool __VERIFIER_nondet_bool(void)
{
	return (nondet_u8() & 1) != 0;
}
#endif

#endif /* QP_SVCOMP_ENV_H */
