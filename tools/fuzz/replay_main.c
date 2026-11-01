/* replay_main.c: run a law imported from a libFuzzer target (tools/qp import-fuzz) natively on concrete
 * inputs: `tools/qp replay`.  Untrusted test tooling, like quickproof/runtime/fuzz_driver.c.
 *
 * The law (harness/LAW.c, built with -Dmain=harness_main) draws its inputs from quickproof.h's nondet_*;
 * here they come from the input files given on the command line, in the order the generated driver draws
 * them (the replay protocol of tools/qp import-fuzz):
 *   nondet_size()        the length of the next input file;
 *   nondet_bytes(b, n)   the bytes of that file (n is its length);
 *   nondet_u8()          1 if another input file follows (the stateful driver's "one more call?"), else 0;
 *   nondet_u32()         0 (not drawn by the generated driver).
 * One process is one execution of the law: with --stateful the files are the successive calls of one
 * libFuzzer process, otherwise one file is one call.
 *
 * Verdict: exit 0 = passes; a failing gp_assert (a null store: SIGSEGV) or a sanitizer report (abort:
 * SIGABRT) = fails; exit 3 = an assumption (gp_assume) is false, e.g. the input is longer than --max-len:
 * the law says nothing about it.
 *
 * usage: replay FILE...
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/resource.h>

int harness_main(void);

static unsigned char **inputs;
static size_t *lengths;
static int n_inputs, next_input, current = -1;

static void die(const char *msg, const char *arg)
{
	fprintf(stderr, "replay: %s%s\n", msg, arg ? arg : "");
	_exit(4);
}

size_t nondet_size(void)
{
	if (next_input >= n_inputs)
		die("the law draws more inputs than given", NULL);
	current = next_input++;
	return lengths[current];
}

void nondet_bytes(uint8_t *buf, size_t n)
{
	if (current < 0 || n != lengths[current])
		die("nondet_bytes does not follow nondet_size (not a law of tools/qp import-fuzz?)", NULL);
	if (n)
		memcpy(buf, inputs[current], n);
}

uint8_t nondet_u8(void)
{
	return next_input < n_inputs;
}

uint32_t nondet_u32(void)
{
	return 0;
}

void gp_assert(int c)
{
	if (!c) {
		fprintf(stderr, "replay: gp_assert failed (a crash of the fuzz target)\n");
		fflush(stderr);
		volatile int *p = 0;
		*p = 0;
	}
}

void gp_assume(int c)
{
	if (!c) {
		fprintf(stderr, "replay: gp_assume failed (the law does not cover this input)\n");
		_exit(3);
	}
}

/* As in fuzz_driver.c: a sanitizer report must end the run by a signal. */
const char *__asan_default_options(void) { return "abort_on_error=1:detect_leaks=0"; }
const char *__ubsan_default_options(void) { return "abort_on_error=1:halt_on_error=1:print_stacktrace=1"; }

int main(int argc, char **argv)
{
	/* A failing run must not dump core (slow; as fuzz_driver.c: 1, not 0, for piped core_pattern handlers). */
	struct rlimit no_core = {1, 1};
	setrlimit(RLIMIT_CORE, &no_core);
	n_inputs = argc - 1;
	inputs = calloc((size_t) (n_inputs ? n_inputs : 1), sizeof *inputs);
	lengths = calloc((size_t) (n_inputs ? n_inputs : 1), sizeof *lengths);
	if (!inputs || !lengths)
		die("out of memory", NULL);
	for (int i = 0; i < n_inputs; ++i) {
		FILE *f = fopen(argv[i + 1], "rb");
		if (!f)
			die("cannot open ", argv[i + 1]);
		size_t cap = 4096, len = 0, r;
		unsigned char *b = malloc(cap);
		while (b && (r = fread(b + len, 1, cap - len, f)) > 0) {
			len += r;
			if (len == cap)
				b = realloc(b, cap *= 2);
		}
		if (!b)
			die("out of memory", NULL);
		fclose(f);
		inputs[i] = b;
		lengths[i] = len;
	}
	harness_main();
	if (next_input != n_inputs)
		fprintf(stderr, "replay: note: %d of %d inputs used\n", next_input, n_inputs);
	return 0;
}
