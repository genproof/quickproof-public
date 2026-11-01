// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh): reach_error() has an empty body, and a call of it
// is still a violation (x == 3).

extern int __VERIFIER_nondet_int(void);
void reach_error() { }
int main() { if (__VERIFIER_nondet_int() == 3) reach_error(); return 0; }
