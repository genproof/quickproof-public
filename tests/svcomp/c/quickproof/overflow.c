// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): a signed overflow (x + INT_MAX for x > 0).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "overflow.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_int(void);

int main()
{
	int x = __VERIFIER_nondet_int();
	int y = 0;
	if (x > 0)
		y = x + 2147483647;
	if (y == 1)
		return 1;
	return 0;
}
