// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): fresh heap memory holds arbitrary values (reading it is defined), calloc zeroes, alloca does not fail.

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "heap-arbitrary.c", 0, "reach_error"); }
extern void *malloc(unsigned long);
extern void *calloc(unsigned long, unsigned long);
extern void free(void *);
extern void *alloca(unsigned long);

int main()
{
	unsigned int *p = malloc(4 * sizeof(unsigned int));
	unsigned int t;
	int *z;
	char *a;
	if (p == 0)
		return 0;
	t = p[1] | p[2];
	p[0] = t;
	z = calloc(4, sizeof(int));
	if (z != 0) {
		if (z[3] != 0)
			reach_error();
		free(z);
	}
	a = alloca(16);
	a[15] = a[0];
	free(p);
	return 0;
}
