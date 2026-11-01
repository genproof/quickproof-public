// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): an out-of-bounds write (n == 16).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "heap-oob.c", 0, "reach_error"); }
extern unsigned int __VERIFIER_nondet_uint(void);
extern void *malloc(unsigned long);
extern void free(void *);

int main()
{
	unsigned int n = __VERIFIER_nondet_uint();
	int *a;
	if (n > 16)
		return 0;
	a = malloc(16 * sizeof(int));
	if (a == 0)
		return 0;
	a[n] = 1;
	free(a);
	return 0;
}
