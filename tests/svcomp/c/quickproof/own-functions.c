// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): the task defines __VERIFIER_assume and strlen itself (left to it).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "own-functions.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_int(void);
extern void abort(void);

void __VERIFIER_assume(int cond)
{
	if (!cond) {
		abort();
	}
}

unsigned long strlen(const char *s)
{
	unsigned long i = 0;
	while (s[i] != 0)
		i++;
	return i;
}

int main()
{
	char s[4] = "abc";
	int k = __VERIFIER_nondet_int();
	__VERIFIER_assume(k >= 0 && k < 3);
	s[k] = 0;
	if (strlen(s) != (unsigned long) k)
		reach_error();
	return 0;
}
