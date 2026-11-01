// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): free() of a block from alloca is an invalid free.

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "alloca-free.c", 0, "reach_error"); }
extern void *alloca(unsigned long);
extern void free(void *);

int main()
{
	char *p = alloca(8);
	p[0] = 1;
	free(p);
	return 0;
}
