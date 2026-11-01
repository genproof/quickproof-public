// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): a block is not freed on some paths (also before exit).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "leak.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_int(void);
extern void *malloc(unsigned long);
extern void free(void *);
extern void exit(int);

int main()
{
	int *p = malloc(sizeof(int));
	int k = __VERIFIER_nondet_int();
	if (p == 0)
		return 0;
	if (k == 1)
		exit(0);
	if (k != 0)
		free(p);
	return 0;
}
