/* tools/fuzz/law_libfuzzer.c: run a law as a coverage-guided libFuzzer target (`tools/qp fuzz --libfuzzer`).
 * Untrusted test tooling, like runtime/fuzz_driver.c: it adds nothing to the trusted base, and a crash it finds
 * is a CANDIDATE counterexample of the law, to be replayed and triaged (docs/QP.md, "Laws as libFuzzer targets").
 *
 * The law (harness/LAW.c built with -Dmain=harness_main, unmodified) draws its inputs from quickproof.h's
 * nondet_*; here they come from the bytes of the fuzzer's input, FuzzedDataProvider-style: scalars from the END
 * of the input, byte buffers from the FRONT, so that a mutation of one kind does not shift the other.
 *   nondet_u8()          one byte;
 *   nondet_u32()         a tag byte t and, by t >> 6, the shapes of runtime/fuzz_driver.c's gp_shape chosen by
 *   nondet_size()        the input instead of a PRNG: 0: t & 63 (small); 1: MAX - (t & 63) (near the top);
 *                        2: (t & 63) << 8 | one more byte (0..16383); 3: 4 (u32) or 8 (size) more bytes, little
 *                        endian: any value.  Every value of the type can be drawn;
 *   nondet_bytes(b, n)   the next n bytes from the front;
 *   quickproof_rnd()     8 bytes, little endian (the project's env.c builds its distributions on it).
 * When the input runs out the draws go on deterministically: the first QP_LF_ZERO_TAIL draws past the end
 * (default 16) return zeros (a short read: the missing bytes are 0), so the empty input is the all-zero run; the
 * later ones a pseudo-random stream seeded by the input (scalar bytes below 64, i.e. small values; buffer bytes and
 * quickproof_rnd unrestricted), so that a law or a shim that draws again until it gets a fresh value (WireGuard's
 * shim draws an index until it is not in use) ends as it does natively, and so that with --nondet env (8 input
 * bytes per quickproof_rnd) a short input still drives the env file's generator like a native random seed (with a
 * long run of zeros instead, a generator of HTTP status lines produced nothing the law accepts).  After
 * QP_LF_EXHAUSTED_DRAWS draws past the end (default 1<<20) the run is abandoned like a failing assume: a law that
 * keeps drawing after the input is spent says nothing more (the native driver's draw budget plays the same part).
 *
 * Distributions (`qp fuzz --libfuzzer --nondet`): `env` links the project's env.c (or env/LAW.c), as the native
 * runs do, so its nondet_* shape the input bytes through quickproof_rnd (structured generators, allocation-failure
 * knobs, which draw from the same input); `direct` compiles the env file with
 * its nondet_* renamed (its other functions stay) and the definitions above are used.  The ones here are weak, so
 * an env file's nondet_* take precedence.
 *
 * Checks.  A failing gp_assert prints "qp-libfuzzer: gp_assert failed" and aborts: a crash.  A failing gp_assume
 * rejects the input: the run is abandoned (longjmp out of harness_main) and LLVMFuzzerTestOneInput returns 0.  A
 * law of an older framework that fails a check by a null store crashes under ASan the same way.  exit(), _exit()
 * and _Exit() during a run end the run normally (as the native driver's forked child: an exit is not a
 * finding); abort(), a sanitizer report, a timeout and the RSS limit are crashes, as natively.
 *
 * One process, many inputs: what a forked child of the native driver gets fresh is reset before every input here:
 *   - the law's global state: the writable data of the law's shared object (law.so: the harness, the library
 *     units, the env file), i.e. its .data, .bss and the like, is copied once before the first input and copied
 *     back before every input.  Excluded: the RELRO part, the GOT, the init/fini arrays, the sanitizer coverage
 *     sections and ASan's metadata (constant after loading);
 *   - the heap: the law's malloc, calloc, realloc, free, strdup and strndup are wrapped (ld --wrap, in the link
 *     of law.so), and every block still allocated at the end of a run is freed before the next input.
 * NOT reset: thread-local storage (errno included), the C library's own state (stdio buffers and streams, rand(),
 * strtok(), locale, environment), open file descriptors, signal handlers, and blocks allocated by the C library
 * on the law's behalf through other entry points (getline, asprintf, posix_memalign, aligned_alloc, ...): a law
 * that depends on these across runs may behave differently than under the native driver.  Replay a crash with
 * the standalone build (QP_LF_STANDALONE below), one fresh process per input, before believing it.
 *
 * Environment: QP_LF_STATS=1 prints the tally of the runs at exit (completed, rejected by gp_assume, ended by
 * exit, input exhausted); QP_LF_VERBOSE=1 the restored sections; QP_LF_ZERO_TAIL=N the zero draws past the end of
 * the input; QP_LF_EXHAUSTED_DRAWS=N the draw budget past the end; QP_LF_NO_RESET=1 turns the reset of globals
 * and heap off (to see what it does; tests only).
 *
 * Allocation (the defaults below, __asan_default_options): detect_leaks=0, as the native runs (a law that wants
 * leak freedom asserts it; the blocks are freed between runs anyway); allocator_may_return_null=1 and
 * max_allocation_size_mb=1024: a malloc of more than 1 GiB returns NULL, which the theorem's malloc may do (VST's
 * malloc_spec'), instead of an ASan report (natively such a request is an ASan report or succeeds).  qp runs the
 * fuzzer with -malloc_limit_mb above that bound, so libFuzzer's own malloc limit never fires first.  The
 * environment's ASAN_OPTIONS can override these.
 *
 * Builds (tools/qp does both):
 *   libFuzzer:   the law's objects with clang -fsanitize=address,undefined,fuzzer-no-link -fPIC into law.so
 *                (-Wl,-Bsymbolic,-z,now and --wrap=malloc,calloc,realloc,free,strdup,strndup,exit,_exit,_Exit);
 *                this file, uninstrumented, linked with clang -fsanitize=fuzzer,address,undefined against law.so;
 *   standalone:  -DQP_LF_STANDALONE: a main that replays input files, each in a fresh forked process, linked
 *                statically with the law the way the native runs build it (gcc, ASan/UBSan, no wrapping).
 *                Exit status 0 = every input passed or was not covered; 1 = some input failed.
 */
#define _GNU_SOURCE
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int harness_main(void);

/* ---- the input -------------------------------------------------------------------------------------- */

static const uint8_t *qp_in;
static size_t qp_front, qp_back;          /* bytes [qp_front, qp_back) are not consumed yet */
static unsigned long qp_past_end, qp_past_end_max = 1UL << 20, qp_zero_tail = 16;
static uint64_t qp_tail_state;           /* the pseudo-random stream past the end (xorshift64), seeded by the input */
static jmp_buf qp_run_env;
static int qp_running;                    /* inside harness_main */
enum { QP_END_NORMAL, QP_END_REJECTED, QP_END_EXIT, QP_END_EXHAUSTED };
static struct { unsigned long runs, completed, rejected, exited, exhausted; } qp_stats;

static void qp_end_run(int how)
{
	if (!qp_running) {                /* outside a run (cannot happen from a law): end the process */
		fprintf(stderr, "qp-libfuzzer: run ended outside harness_main (%d)\n", how);
		_exit(how == QP_END_REJECTED ? 3 : 0);
	}
	longjmp(qp_run_env, how);
}

static void qp_past_end_draw(void)
{
	if (++qp_past_end > qp_past_end_max)
		qp_end_run(QP_END_EXHAUSTED);
}

/* One draw past the end: 0 for the first qp_zero_tail ones, then the next value of the pseudo-random stream. */
static uint64_t qp_tail(void)
{
	qp_past_end_draw();
	if (qp_past_end <= qp_zero_tail)
		return 0;
	uint64_t x = qp_tail_state;
	x ^= x << 13;
	x ^= x >> 7;
	x ^= x << 17;
	qp_tail_state = x;
	return x;
}

static uint8_t qp_scalar_byte(void)
{
	if (qp_back > qp_front)
		return qp_in[--qp_back];
	return (uint8_t) (qp_tail() & 63);   /* a tag byte below 64: a small value (qp_shaped) */
}

static uint64_t qp_scalar_le(unsigned n)
{
	uint64_t v = 0;
	for (unsigned i = 0; i < n; ++i)
		v |= (uint64_t) qp_scalar_byte() << (8 * i);
	return v;
}

/* gp_shape of runtime/fuzz_driver.c, the shape chosen by the input: small, near the top, mid-range, anything. */
static uint64_t qp_shaped(uint64_t max, unsigned width)
{
	const uint8_t t = qp_scalar_byte();
	switch (t >> 6) {
	case 0: return t & 63u;
	case 1: return max - (t & 63u);
	case 2: return ((uint64_t) (t & 63u) << 8 | qp_scalar_byte()) & max;
	default: return qp_scalar_le(width) & max;
	}
}

static uint64_t qp_rnd(void)
{
	if (qp_back - qp_front >= 8 || qp_past_end < qp_zero_tail)
		return qp_scalar_le(8);
	return qp_tail();                     /* past the zeros: unrestricted, as the native driver's PRNG */
}
uint64_t quickproof_rnd(void) { return qp_rnd(); }

__attribute__((weak)) uint8_t nondet_u8(void) { return qp_scalar_byte(); }
__attribute__((weak)) uint32_t nondet_u32(void) { return (uint32_t) qp_shaped(UINT32_MAX, 4); }
__attribute__((weak)) size_t nondet_size(void) { return (size_t) qp_shaped(SIZE_MAX, 8); }
__attribute__((weak)) void nondet_bytes(uint8_t *buf, size_t n)
{
	size_t k = qp_back - qp_front;
	if (k > n)
		k = n;
	if (k)
		memcpy(buf, qp_in + qp_front, k);
	qp_front += k;
	if (k < n) {
		if (qp_past_end < qp_zero_tail) {
			memset(buf + k, 0, n - k);
			qp_past_end_draw();
		} else {
			for (size_t i = k; i < n; ++i)
				buf[i] = (uint8_t) qp_tail();
		}
	}
}

/* ---- the checks ------------------------------------------------------------------------------------- */

__attribute__((weak)) void gp_assert(int c)
{
	if (!c) {
		fprintf(stderr, "qp-libfuzzer: gp_assert failed (called from %p)\n", __builtin_return_address(0));
		abort();
	}
}

__attribute__((weak)) void gp_assume(int c)
{
	if (!c)
		qp_end_run(QP_END_REJECTED);
}

/* In sanitizer builds a report must end the run by a signal, as in fuzz_driver.c; the allocation policy is in the
 * file header. */
const char *__asan_default_options(void)
{
	return "abort_on_error=1:detect_leaks=0:allocator_may_return_null=1:max_allocation_size_mb=1024";
}
const char *__ubsan_default_options(void) { return "abort_on_error=1:halt_on_error=1:print_stacktrace=1"; }

/* One run of the law on `data`.  Returns how it ended (QP_END_*). */
static int qp_run(const uint8_t *data, size_t size)
{
	qp_in = data;
	qp_front = 0;
	qp_back = size;
	qp_past_end = 0;
	/* the seed of the stream past the end: FNV-1a of the size and the first 256 bytes, never 0 */
	uint64_t h = 0xcbf29ce484222325ULL ^ size;
	for (size_t i = 0; i < size && i < 256; ++i)
		h = (h ^ data[i]) * 0x100000001b3ULL;
	qp_tail_state = h ? h : 1;
	qp_stats.runs++;
	int how = setjmp(qp_run_env);
	if (how == 0) {
		qp_running = 1;
		harness_main();
		how = QP_END_NORMAL;
	}
	qp_running = 0;
	switch (how) {
	case QP_END_NORMAL: qp_stats.completed++; break;
	case QP_END_REJECTED: qp_stats.rejected++; break;
	case QP_END_EXIT: qp_stats.exited++; break;
	default: qp_stats.exhausted++; break;
	}
	return how;
}

static void qp_options(void)
{
	const char *s = getenv("QP_LF_EXHAUSTED_DRAWS");
	if (s && *s)
		qp_past_end_max = strtoul(s, 0, 0);
	s = getenv("QP_LF_ZERO_TAIL");
	if (s && *s)
		qp_zero_tail = strtoul(s, 0, 0);
}

#ifndef QP_LF_STANDALONE
/* ===================================================================================================== */
/* libFuzzer build                                                                                        */
/* ===================================================================================================== */
#include <dlfcn.h>
#include <elf.h>
#include <fcntl.h>
#include <link.h>
#include <sys/mman.h>
#include <sys/stat.h>

/* ---- exit during a run: the end of the run (law.so is linked with --wrap=exit,_exit,_Exit) ---------- */

void __wrap_exit(int status)
{
	if (qp_running)
		qp_end_run(QP_END_EXIT);
	exit(status);
}
void __wrap__exit(int status)
{
	if (qp_running)
		qp_end_run(QP_END_EXIT);
	_exit(status);
}
void __wrap__Exit(int status)
{
	if (qp_running)
		qp_end_run(QP_END_EXIT);
	_Exit(status);
}

/* ---- the law's heap: blocks allocated during a run, freed before the next one --------------------- */
/* An open-addressing set of live blocks in mmap'd memory (never part of a restored region). */

static uintptr_t *qp_live;
static size_t qp_live_cap, qp_live_n;     /* cap: a power of two; slots 0 = empty, 1 = deleted */

static size_t qp_slot(uintptr_t p, size_t cap) { return (size_t) ((p >> 4) * 0x9E3779B97F4A7C15ULL) & (cap - 1); }

static void qp_live_add(void *ptr);

static void qp_live_grow(void)
{
	uintptr_t *old = qp_live;
	size_t oldcap = qp_live_cap;
	qp_live_cap = oldcap ? oldcap * 2 : 4096;
	qp_live = mmap(0, qp_live_cap * sizeof *qp_live, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (qp_live == MAP_FAILED) {
		fprintf(stderr, "qp-libfuzzer: mmap failed\n");
		abort();
	}
	qp_live_n = 0;
	for (size_t i = 0; i < oldcap; ++i)
		if (old[i] > 1)
			qp_live_add((void *) old[i]);
	if (old)
		munmap(old, oldcap * sizeof *old);
}

static void qp_live_add(void *ptr)
{
	if (!ptr)
		return;
	if ((qp_live_n + 1) * 2 > qp_live_cap)
		qp_live_grow();
	size_t i = qp_slot((uintptr_t) ptr, qp_live_cap);
	while (qp_live[i] > 1)
		i = (i + 1) & (qp_live_cap - 1);
	qp_live[i] = (uintptr_t) ptr;
	qp_live_n++;
}

static int qp_live_del(void *ptr)
{
	if (!ptr || !qp_live_cap)
		return 0;
	size_t i = qp_slot((uintptr_t) ptr, qp_live_cap);
	while (qp_live[i]) {
		if (qp_live[i] == (uintptr_t) ptr) {
			qp_live[i] = 1;
			qp_live_n--;
			return 1;
		}
		i = (i + 1) & (qp_live_cap - 1);
	}
	return 0;
}

static void qp_live_free_all(void)
{
	for (size_t i = 0; i < qp_live_cap; ++i) {
		if (qp_live[i] > 1)
			free((void *) qp_live[i]);
		qp_live[i] = 0;
	}
	qp_live_n = 0;
}

void *__wrap_malloc(size_t n) { void *p = malloc(n); qp_live_add(p); return p; }
void *__wrap_calloc(size_t m, size_t n) { void *p = calloc(m, n); qp_live_add(p); return p; }
void __wrap_free(void *p) { qp_live_del(p); free(p); }
void *__wrap_realloc(void *p, size_t n)
{
	void *q = realloc(p, n);
	if (q || n == 0)                  /* moved, or freed (realloc(p, 0)) */
		qp_live_del(p);
	qp_live_add(q);
	return q;
}
char *__wrap_strdup(const char *s) { char *p = strdup(s); qp_live_add(p); return p; }
char *__wrap_strndup(const char *s, size_t n) { char *p = strndup(s, n); qp_live_add(p); return p; }

/* ---- the law's global state: the writable data of law.so, saved before the first input -------------- */

struct qp_region { uint8_t *addr; size_t len; uint8_t *copy; char name[48]; };
static struct qp_region qp_regions[64];
static int qp_nregions, qp_saved;
static size_t qp_saved_bytes;
static int qp_verbose, qp_no_reset;

/* Copied by hand, uninstrumented: the regions hold ASan's redzones around the globals, which ASan's memcpy
 * interceptor would report.  Volatile stores, so that the compiler does not turn the loop into a memcpy call. */
__attribute__((no_sanitize("address", "undefined")))
static void qp_copy(uint8_t *dst, const uint8_t *src, size_t n)
{
	volatile uint8_t *d = dst;
	size_t i = 0;
	while (i < n && ((uintptr_t) (dst + i) & 7))
		d[i] = src[i], i++;
	if (((uintptr_t) (src + i) & 7) == 0) {
		for (; i + 8 <= n; i += 8)
			*(volatile uint64_t *) (dst + i) = *(const uint64_t *) (src + i);
	}
	for (; i < n; ++i)
		d[i] = src[i];
}

static int qp_excluded_section(const char *name)
{
	static const char *const prefixes[] = {
		"__sancov", "asan_globals", ".got", ".dynamic", ".init_array", ".fini_array", ".preinit_array",
		".data.rel.ro", ".tm_clone_table", ".tdata", ".tbss", 0,
	};
	for (int i = 0; prefixes[i]; ++i)
		if (strncmp(name, prefixes[i], strlen(prefixes[i])) == 0)
			return 1;
	return 0;
}

struct qp_find { const char *path; ElfW(Addr) base; uintptr_t relro_lo, relro_hi; int found; };

static int qp_find_cb(struct dl_phdr_info *info, size_t size, void *arg)
{
	struct qp_find *f = arg;
	(void) size;
	if (!info->dlpi_name || strcmp(info->dlpi_name, f->path) != 0)
		return 0;
	f->base = info->dlpi_addr;
	for (int i = 0; i < info->dlpi_phnum; ++i)
		if (info->dlpi_phdr[i].p_type == PT_GNU_RELRO) {
			f->relro_lo = info->dlpi_addr + info->dlpi_phdr[i].p_vaddr;
			f->relro_hi = f->relro_lo + info->dlpi_phdr[i].p_memsz;
		}
	f->found = 1;
	return 1;
}

static void qp_die(const char *msg, const char *arg)
{
	fprintf(stderr, "qp-libfuzzer: %s%s\n", msg, arg ? arg : "");
	_exit(4);
}

/* The regions: the SHF_WRITE|SHF_ALLOC sections of law.so (the object that defines harness_main), from its
 * section headers on disk, minus the exclusions (qp_excluded_section and the RELRO segment). */
static void qp_find_regions(void)
{
	void *hm = dlsym(RTLD_DEFAULT, "harness_main");
	Dl_info di;
	if (!hm || !dladdr(hm, &di) || !di.dli_fname)
		qp_die("cannot find the object that defines harness_main", 0);
	struct qp_find f = { di.dli_fname, 0, 0, 0, 0 };
	dl_iterate_phdr(qp_find_cb, &f);
	if (!f.found)
		qp_die("not a loaded object: ", di.dli_fname);
	int fd = open(f.path, O_RDONLY);
	struct stat st;
	if (fd < 0 || fstat(fd, &st) != 0)
		qp_die("cannot open ", f.path);
	const uint8_t *img = mmap(0, (size_t) st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);
	if (img == MAP_FAILED)
		qp_die("cannot map ", f.path);
	const ElfW(Ehdr) *eh = (const void *) img;
	if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 || !eh->e_shoff || eh->e_shstrndx == SHN_UNDEF)
		qp_die("no section headers in ", f.path);
	const ElfW(Shdr) *sh = (const void *) (img + eh->e_shoff);
	const char *names = (const char *) img + sh[eh->e_shstrndx].sh_offset;
	for (int i = 0; i < eh->e_shnum; ++i) {
		const ElfW(Shdr) *s = &sh[i];
		const char *name = names + s->sh_name;
		if ((s->sh_flags & (SHF_ALLOC | SHF_WRITE)) != (SHF_ALLOC | SHF_WRITE) || (s->sh_flags & SHF_TLS) ||
		    !s->sh_size || (s->sh_type != SHT_PROGBITS && s->sh_type != SHT_NOBITS) || qp_excluded_section(name))
			continue;
		uintptr_t lo = f.base + s->sh_addr, hi = lo + s->sh_size;
		if (lo < f.relro_hi && hi > f.relro_lo)
			continue;
		if (qp_nregions == (int) (sizeof qp_regions / sizeof qp_regions[0]))
			qp_die("too many writable sections in ", f.path);
		struct qp_region *r = &qp_regions[qp_nregions++];
		r->addr = (uint8_t *) lo;
		r->len = s->sh_size;
		snprintf(r->name, sizeof r->name, "%s", name);
	}
	munmap((void *) img, (size_t) st.st_size);
	if (qp_verbose) {
		fprintf(stderr, "qp-libfuzzer: law object %s; restored before every input:", f.path);
		for (int i = 0; i < qp_nregions; ++i)
			fprintf(stderr, " %s (%zu bytes)", qp_regions[i].name, qp_regions[i].len);
		fprintf(stderr, "\n");
	}
}

static void qp_save(void)
{
	qp_find_regions();
	for (int i = 0; i < qp_nregions; ++i) {
		struct qp_region *r = &qp_regions[i];
		/* the copy at the same offset modulo 8 as the region, so that qp_copy moves words both ways */
		uint8_t *m = mmap(0, r->len + 8, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (m == MAP_FAILED)
			qp_die("mmap failed", 0);
		r->copy = m + ((uintptr_t) r->addr & 7);
		qp_copy(r->copy, r->addr, r->len);
		qp_saved_bytes += r->len;
	}
	qp_live_grow();
	qp_saved = 1;
}

static void qp_restore(void)
{
	for (int i = 0; i < qp_nregions; ++i)
		qp_copy(qp_regions[i].addr, qp_regions[i].copy, qp_regions[i].len);
	qp_live_free_all();
}

static void qp_report(void)
{
	if (qp_stats.runs)
		fprintf(stderr, "qp-libfuzzer: runs %lu: completed %lu, rejected by gp_assume %lu, ended by exit %lu, "
		        "input exhausted %lu; state restored per input: %zu bytes in %d regions\n",
		        qp_stats.runs, qp_stats.completed, qp_stats.rejected, qp_stats.exited, qp_stats.exhausted,
		        qp_saved_bytes, qp_nregions);
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void) argc;
	(void) argv;
	qp_options();
	qp_verbose = getenv("QP_LF_VERBOSE") != 0;
	qp_no_reset = getenv("QP_LF_NO_RESET") != 0;
	if (getenv("QP_LF_STATS"))
		atexit(qp_report);
	return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	/* Saved at the start of the first input: the law's constructors have run, and libFuzzer has just cleared
	 * the coverage counters (they are excluded anyway). */
	if (!qp_saved)
		qp_save();
	else if (!qp_no_reset)
		qp_restore();
	qp_run(data, size);
	return 0;
}

#else
/* ===================================================================================================== */
/* standalone replay: each input file in a fresh forked process, as the native driver runs a seed           */
/* ===================================================================================================== */
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>

static uint8_t *qp_read_file(const char *path, size_t *len)
{
	FILE *f = fopen(path, "rb");
	if (!f)
		return 0;
	size_t cap = 4096, n = 0, r;
	uint8_t *b = malloc(cap);
	while (b && (r = fread(b + n, 1, cap - n, f)) > 0) {
		n += r;
		if (n == cap)
			b = realloc(b, cap *= 2);
	}
	fclose(f);
	*len = n;
	return b;
}

int main(int argc, char **argv)
{
	struct rlimit no_core = {1, 1};   /* as fuzz_driver.c: no core dumps (1, not 0, for piped core_pattern) */
	setrlimit(RLIMIT_CORE, &no_core);
	qp_options();
	int failed = 0;
	if (argc < 2) {
		fprintf(stderr, "usage: %s INPUT...\n", argv[0]);
		return 2;
	}
	for (int i = 1; i < argc; ++i) {
		size_t len = 0;
		uint8_t *data = qp_read_file(argv[i], &len);
		if (!data) {
			fprintf(stderr, "qp-replay: cannot read %s\n", argv[i]);
			failed = 1;
			continue;
		}
		fflush(stdout);
		pid_t pid = fork();
		if (pid == 0) {
			int how = qp_run(data, len);
			_exit(how == QP_END_REJECTED ? 3 : how == QP_END_EXHAUSTED ? 5 : 0);
		}
		int st;
		waitpid(pid, &st, 0);
		if (WIFSIGNALED(st)) {
			failed = 1;
			printf("%s: FAILED (signal %d)\n", argv[i], WTERMSIG(st));
		} else if (WEXITSTATUS(st) == 3) {
			printf("%s: not covered (a gp_assume is false)\n", argv[i]);
		} else if (WEXITSTATUS(st) == 5) {
			printf("%s: abandoned (the law kept drawing past the end of the input)\n", argv[i]);
		} else if (WEXITSTATUS(st) != 0 && WEXITSTATUS(st) != 1) {
			printf("%s: exit %d\n", argv[i], WEXITSTATUS(st));
		} else {
			printf("%s: pass%s\n", argv[i], WEXITSTATUS(st) ? " (the law exited with status 1)" : "");
		}
		free(data);
	}
	return failed;
}
#endif
