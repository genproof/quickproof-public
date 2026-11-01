/* quickproof runtime/fuzz_driver.c: run a harness natively, once per seed, in a forked child.
 *
 * The harness's `main` is built as harness_main (-Dmain=harness_main), unmodified.  The environment
 * functions of include/quickproof.h are implemented here with a seeded PRNG, as weak symbols: a project
 * that wants value distributions tuned to its code defines its own nondet_* and they take precedence.
 *
 * A run that ends by a signal is reported: a failed check (the harness's undefined behaviour,
 * e.g. a null store: SIGSEGV), a crash, or SIGALRM (timeout).  Build the harness with -O0 and
 * -fno-delete-null-pointer-checks: an optimising compiler may delete the paths that reach a
 * deliberate undefined behaviour (seen with gcc -O1: a mutant went undetected).
 *
 * A harness that runs forever (drawing inputs in a loop) is stopped after a budget of random draws:
 * the run then ends normally (and dumps coverage in --coverage builds).
 *
 * ASSUME-AWARE TALLY (untrusted tooling; see docs/HARNESSES.md "Non-vacuity gate").  The driver keeps,
 * per call site (identified by the caller's return address), how often each gp_assume was reached and
 * how often it accepted the input, and how often each gp_assert was reached.  Counters live in a shared
 * anonymous mmap so they survive each forked child and accumulate across seeds.  From the tally it prints
 * a per-assume acceptance rate, a per-assert reach count, and a NON-VACUITY GATE verdict: the asserts of
 * the harness must actually be reached by inputs that pass the assumes.  This is a QUALITY gate on the
 * harness, NOT a soundness component -- soundness rests only on the proofs; the gate only catches a
 * vacuous (or too-tight) assume.  With GP_GATE=1 in the environment the exit status reflects the gate.
 *
 * usage: fuzz [runs] [first_seed] [budget, 0 = none] [timeout_s]
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/resource.h>

int harness_main(void);

static uint64_t s;
static long draws, budget;
extern void __gcov_dump(void) __attribute__((weak));   /* present in --coverage builds */

/* Assume-aware tally, in shared memory so forked children accumulate into it (see the file header).
 * Sites are keyed by the caller's return address; one entry per distinct gp_assume/gp_assert call site.
 * Children run one at a time (fork + waitpid), so no locking is needed. */
#define GP_MAX_SITES 128
struct gp_site { void *pc; long reached; long passed; };   /* passed unused for asserts */
struct gp_stats {
    long completed;            /* children that reached the end of harness_main (passed every assume hit) */
    long rejected;             /* children abandoned by a failing gp_assume */
    int  n_assume, n_assert;
    int  overflow;             /* more than GP_MAX_SITES distinct sites of one kind */
    struct gp_site assume[GP_MAX_SITES];
    struct gp_site assert_[GP_MAX_SITES];
};
static struct gp_stats *stats;   /* NULL until main maps it; the primitives tolerate that */

static struct gp_site *gp_site_of(struct gp_site *tab, int *n, void *pc)
{
    for (int i = 0; i < *n; ++i) if (tab[i].pc == pc) return &tab[i];
    if (*n >= GP_MAX_SITES) { stats->overflow = 1; return 0; }
    tab[*n].pc = pc;
    return &tab[(*n)++];
}

/* The seeded PRNG of the run; project-specific nondet_* use it too, so a seed replays a run. */
uint64_t quickproof_rnd(void)
{
    if (budget > 0 && ++draws > budget) {
        if (__gcov_dump) __gcov_dump();
        _exit(0);
    }
    s ^= s << 13; s ^= s >> 7; s ^= s << 17;
    return s;
}
#define rnd quickproof_rnd

/* Small values and values near the top of the range are where the bugs are. */
static uint64_t gp_shape(uint64_t max)
{
    switch (rnd() % 4) {
    case 0: return rnd() % 17;
    case 1: return max - rnd() % 17;
    case 2: return rnd() % 4096;
    default: return rnd() & max;
    }
}

__attribute__((weak)) uint8_t nondet_u8(void) { return (uint8_t) gp_shape(UINT8_MAX); }
__attribute__((weak)) uint32_t nondet_u32(void) { return (uint32_t) gp_shape(UINT32_MAX); }
__attribute__((weak)) size_t nondet_size(void) { return (size_t) gp_shape(SIZE_MAX); }
__attribute__((weak)) void nondet_bytes(uint8_t *buf, size_t n)
{
    for (size_t i = 0; i < n; ++i) buf[i] = (uint8_t) rnd();
}

/* The check primitives of quickproof.h.  A failed gp_assert is the harness's undefined behaviour
 * (a null store: SIGSEGV, caught as a finding).  A failed gp_assume abandons the seed -- the input
 * did not meet the assumption, so the run carries no information.  (The Coq realizability witness of
 * gp_assume is the diverging function; _exit is its native equivalent, and does not burn the timeout.)
 * Both also record their call site in the shared tally for the non-vacuity gate. */
void gp_assert(int c)
{
    if (stats) { struct gp_site *e = gp_site_of(stats->assert_, &stats->n_assert, __builtin_return_address(0)); if (e) e->reached++; }
    if (!c) { volatile int *p = 0; *p = 0; }
}
void gp_assume(int c)
{
    if (stats) {
        struct gp_site *e = gp_site_of(stats->assume, &stats->n_assume, __builtin_return_address(0));
        if (e) { e->reached++; if (c) e->passed++; }
    }
    if (!c) { if (stats) stats->rejected++; _exit(0); }   /* skip this input, draw the next seed */
}

/* In sanitizer builds (-fsanitize=address,undefined) a finding must end the run by a signal, like a
 * failed check: by default ASan exits with status 1 and would be counted as a normal run. */
const char *__asan_default_options(void) { return "abort_on_error=1"; }
const char *__ubsan_default_options(void) { return "abort_on_error=1:halt_on_error=1:print_stacktrace=1"; }

int main(int argc, char **argv)
{
    const long runs = argc > 1 ? atol(argv[1]) : 1000;
    const long first = argc > 2 ? atol(argv[2]) : 1;
    budget = argc > 3 ? atol(argv[3]) : 0;
    const unsigned timeout = argc > 4 ? (unsigned) atoi(argv[4]) : 60;
    long ok = 0, failed = 0;
    /* A failing run must not dump core (slow).  1, not 0: with a piped core_pattern (apport, systemd-
     * coredump) the kernel ignores a limit of 0 and skips the dump only for a limit of 1. */
    struct rlimit no_core = {1, 1};
    setrlimit(RLIMIT_CORE, &no_core);
    /* Shared so each forked child's tally survives into the parent and accumulates across seeds. */
    stats = mmap(0, sizeof *stats, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (stats == MAP_FAILED) { perror("mmap"); stats = 0; }
    else memset(stats, 0, sizeof *stats);
    for (long seed = first; seed < first + runs; ++seed) {
        pid_t pid = fork();
        if (pid == 0) {
            s = 0x9E3779B97F4A7C15ULL ^ (uint64_t) seed * 0x2545F4914F6CDD1DULL;
            if (s == 0) s = 1;
            alarm(timeout);
            int rc = harness_main();
            if (stats) stats->completed++;   /* reached the end: passed every assume it hit */
            _exit(rc);
        }
        int st;
        waitpid(pid, &st, 0);
        if (WIFSIGNALED(st)) {
            ++failed;
            printf("seed %ld: signal %d%s\n", seed, WTERMSIG(st),
                   WTERMSIG(st) == SIGALRM ? " (timeout)" : "");
        } else ++ok;
    }
    printf("runs %ld: ok %ld, FAILED %ld\n", runs, ok, failed);

    /* Assume-aware summary and the non-vacuity gate (untrusted quality check; see the file header). */
    int gate_fail = 0;
    const char *reason = "ok";
    if (stats) {
        printf("assume-aware tally: completed %ld (passed all assumes), rejected %ld\n",
               stats->completed, stats->rejected);
        printf("gp_assume sites: %d\n", stats->n_assume);
        for (int i = 0; i < stats->n_assume; ++i) {
            struct gp_site *e = &stats->assume[i];
            double rate = e->reached ? 100.0 * (double) e->passed / (double) e->reached : 0.0;
            printf("  assume #%d @%p: passed %ld/%ld (%.1f%%)%s\n",
                   i, e->pc, e->passed, e->reached, rate,
                   e->passed == 0 ? "  <-- never satisfied" : "");
            if (e->passed == 0) { gate_fail = 1; reason = "an assume is never satisfied (vacuous/over-tight)"; }
        }
        printf("gp_assert sites: %d\n", stats->n_assert);
        for (int i = 0; i < stats->n_assert; ++i)
            printf("  assert #%d @%p: reached %ld\n", i, stats->assert_[i].pc, stats->assert_[i].reached);
        if (stats->n_assert == 0) {
            gate_fail = 1;
            reason = "no gp_assert was reached (nothing proved past the assumes)";
        }
        if (stats->overflow)
            printf("note: more than %d distinct sites of one kind; tally is partial\n", GP_MAX_SITES);
        printf("non-vacuity gate: %s (%s)\n", gate_fail ? "FAIL" : "PASS", reason);
    } else {
        printf("non-vacuity gate: SKIPPED (no shared tally)\n");
    }

    /* GP_GATE=1: the exit status reflects the gate too, so a pipeline can gate on it.  Without it the
     * status is unchanged (findings only), so the driver stays a drop-in for existing fuzz builds. */
    if (getenv("GP_GATE") && gate_fail) return 2;
    return failed != 0;
}
