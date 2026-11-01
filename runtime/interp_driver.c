/* quickproof runtime/interp_driver.c: run a harness under CompCert's reference interpreter
 * (`ccomp -interp`, tools/interp.sh), i.e. under the Clight semantics the theorem is about.
 *
 * Native runs (fuzz_driver.c) miss undefined behaviour that the compiler happens to tolerate but
 * CompCert's semantics does not, e.g. pointer arithmetic or comparisons outside an object, or
 * pointer-to-integer tricks: the interpreter stops with "Stuck state" and names the expression.
 * Such a stop is exactly a counterexample to harness_safe.
 *
 * The harness's `main` is built as harness_main; the environment functions are a seeded PRNG.
 * One interpreter process runs the seeds GP_FIRST .. GP_FIRST+GP_RUNS-1 in turn and prints each
 * seed before its run, so the last seed printed before a stop is the failing one.
 *
 * A law that carries its own copies of the C library's declarations (a preprocessed SV-COMP task, whose
 * shim tools/svcomp/svcomp_env.h defines QP_NO_SYSTEM_HEADERS) would conflict with the system headers:
 * then no header is included, and the driver's types are the built-in ones they are on x86-64 LP64.
 */
#ifndef QP_NO_SYSTEM_HEADERS
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#else
extern int printf(const char *fmt, ...);
#define size_t unsigned long
#define uint8_t unsigned char
#define uint32_t unsigned int
#define uint64_t unsigned long
#endif

#ifndef GP_FIRST
#define GP_FIRST 1
#endif
#ifndef GP_RUNS
#define GP_RUNS 20
#endif

int harness_main(void);


static uint64_t s;
uint64_t quickproof_rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
#define rnd quickproof_rnd

/* The same value shapes as fuzz_driver.c: small values, values near the top, anything. */
static uint64_t gp_shape(uint64_t max)
{
    switch (rnd() % 4) {
    case 0: return rnd() % 17;
    case 1: return max - rnd() % 17;
    case 2: return rnd() % 4096;
    default: return rnd() & max;
    }
}

#ifndef GP_CUSTOM_NONDET   /* else the project's value distributions (tools/interp.sh GP_ENV=...) */
uint8_t nondet_u8(void) { return (uint8_t) gp_shape(255); }
uint32_t nondet_u32(void) { return (uint32_t) gp_shape(4294967295U); }
size_t nondet_size(void) { return (size_t) gp_shape((size_t) -1); }
void nondet_bytes(uint8_t *buf, size_t n)
{
    size_t i;
    for (i = 0; i < n; ++i) buf[i] = (uint8_t) rnd();
}
#endif

/* The check primitives of quickproof.h (fixed contract, so not under GP_CUSTOM_NONDET).  Under the
 * interpreter -- the Clight semantics the theorem is about -- a failed gp_assert stops (a null store),
 * exactly a counterexample to harness_safe; gp_assume diverges when its condition is false, the exact
 * realizability witness of QuickProof.Env.  A seed that violates an assumption therefore does not finish:
 * interp.sh runs ONE seed per `ccomp -interp` with a timeout, so such a seed times out (skipped, like
 * any safe non-terminating run) while a real Stuck state is still reported. */
void gp_assert(int c) { if (!c) { volatile int *p = 0; *p = 0; } }
void gp_assume(int c) { if (!c) for (;;) {} }

int main(void)
{
    long seed;
    for (seed = GP_FIRST; seed < GP_FIRST + GP_RUNS; ++seed) {
        s = 0x9E3779B97F4A7C15ULL ^ (uint64_t) seed * 0x2545F4914F6CDD1DULL;
        if (s == 0) s = 1;
        printf("seed %d\n", (int) seed);
        harness_main();
    }
    printf("runs %d: no stop\n", GP_RUNS);
    return 0;
}

#ifdef QP_NO_SYSTEM_HEADERS
#undef size_t
#undef uint8_t
#undef uint32_t
#undef uint64_t
#endif
