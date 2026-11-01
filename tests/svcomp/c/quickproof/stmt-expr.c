// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): a GNU statement expression, which gcc compiles and
// CompCert does not, so the interpreter gives no verdict (and the cone check reports clightgen's error).

extern void __assert_fail(const char *, const char *, unsigned int, const char *) __attribute__((__nothrow__, __leaf__)) __attribute__((__noreturn__));
void reach_error() { __assert_fail("0", "stmt-expr.c", 0, "reach_error"); }
extern int __VERIFIER_nondet_int(void);

int main()
{
	int x = __VERIFIER_nondet_int();
	int y = ({ int t = x; t & 1; });
	if (y != 0 && y != 1)
		reach_error();
	return 0;
}
