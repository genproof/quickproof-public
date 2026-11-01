// SPDX-FileCopyrightText: 2026 GenProof
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// A test task of tools/qp import-svcomp (tests/qp/svcomp.sh), written in the style of a preprocessed task: it
// carries its own copies of C library declarations, some of which conflict with the system headers (struct
// _IO_FILE, struct __locale_struct, an anonymous div_t), and glibc's assert() expansion, a GNU statement
// expression with __PRETTY_FUNCTION__, and an asm label on a declaration (CompCert does not accept those).
typedef unsigned long size_t;
typedef struct { int quot; int rem; } div_t;
struct _IO_FILE { int qp_test_only; };
typedef struct _IO_FILE FILE;
struct __locale_struct { int qp_test_only; };
typedef struct __locale_struct *locale_t;
extern void __assert_fail (const char *__assertion, const char *__file, unsigned int __line, const char *__function)
     __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__noreturn__));
extern void *malloc (size_t __size) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__malloc__));
extern void free (void *__ptr) __attribute__ ((__nothrow__ , __leaf__));
extern size_t strlen (const char *__s) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
extern void *memset (void *__s, int __c, size_t __n) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__nonnull__ (1)));
extern int strcmp (const char *__s1, const char *__s2) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern int fscanf (FILE *__restrict __stream, const char *__restrict __format, ...) __asm__ ("" "__isoc99_fscanf");
extern int __VERIFIER_nondet_int(void);
void reach_error() { ((void) sizeof ((0) ? 1 : 0), __extension__ ({ if (0) ; else __assert_fail ("0", "glibc-like.c", 17, __extension__ __PRETTY_FUNCTION__); })); }

int main()
{
  char buf[8];
  div_t d;
  int n = __VERIFIER_nondet_int();
  if (n < 0 || n > 7)
    return 0;
  memset(buf, 'a', n);
  buf[n] = 0;
  if (strlen(buf) != (size_t) n)
    reach_error();
  if (n == 3 && strcmp(buf, "aaa") != 0)
    reach_error();
  d.quot = n;
  d.rem = 0;
  ((void) sizeof ((d.quot == n) ? 1 : 0), __extension__ ({ if (d.quot == n) ; else __assert_fail ("d.quot == n", "glibc-like.c", 31, __extension__ __PRETTY_FUNCTION__); }));
  return 0;
}
