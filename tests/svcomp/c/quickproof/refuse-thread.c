// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), refused: threads.

extern void __assert_fail(const char *, const char *, unsigned int, const char *);
void reach_error() { __assert_fail("0", "refuse-thread.c", 0, "reach_error"); }
typedef unsigned long pthread_t;
extern int pthread_create(pthread_t *, const void *, void *(*)(void *), void *);
void *worker(void *arg) { return arg; }
int main() { pthread_t t; pthread_create(&t, 0, worker, 0); return 0; }
