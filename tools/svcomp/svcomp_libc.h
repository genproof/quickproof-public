/* svcomp_libc.h: the C library functions of laws imported from SV-COMP tasks (tools/qp import-svcomp),
 * in plain C, without any header.
 *
 * Copied into projects/NAME/harness/svcomp/ by `tools/qp import-svcomp` (with a provenance line); edit the
 * original in the framework's tools/svcomp/, never the copy.
 *
 * The law includes this file after the task, so the definitions follow the task's own declarations of
 * these functions (from its copy of <string.h>) and are compatible with them.  They are compiled into the
 * law and verified with it, like libc/libc.c (whose memory functions they repeat without headers: a
 * preprocessed task carries its own copies of the C library's declarations, which conflict with the
 * system headers that libc/libc.c includes when tools/interp.sh puts every unit in one translation unit).
 *
 * Only CompCert sees them (__COMPCERT__: clightgen and the interpreter); native runs use the system's
 * C library, as they do for libc/libc.c.  A function the task defines itself is left to the task: the
 * importer defines QP_SVCOMP_OWN_<name> before the law includes this file.
 *
 * Index-based, byte by byte, and without ordering comparisons of pointers (undefined between different
 * objects).  strdup allocates with the task's malloc (svcomp_env.h).
 */
#ifndef QP_SVCOMP_LIBC_H
#define QP_SVCOMP_LIBC_H
#ifdef __COMPCERT__

#ifndef QP_SVCOMP_OWN_memcpy
void *memcpy(void *dest, const void *src, unsigned long n)
{
	unsigned char *d = dest;
	const unsigned char *s = src;
	unsigned long i;
	for (i = 0; i < n; i = i + 1)
		d[i] = s[i];
	return dest;
}
#endif

/* The ranges overlap with d after s exactly when d == s + i for some 0 < i < n (pointer equality is
 * defined between objects); only then is the copy done backwards (libc/libc.c). */
#ifndef QP_SVCOMP_OWN_memmove
void *memmove(void *dest, const void *src, unsigned long n)
{
	unsigned char *d = dest;
	const unsigned char *s = src;
	int backwards = 0;
	unsigned long i;
	for (i = 1; i < n; i = i + 1)
		if (s + i == d) {
			backwards = 1;
			break;
		}
	if (backwards) {
		for (i = n; i > 0; i = i - 1)
			d[i - 1] = s[i - 1];
	} else {
		for (i = 0; i < n; i = i + 1)
			d[i] = s[i];
	}
	return dest;
}
#endif

#ifndef QP_SVCOMP_OWN_memset
void *memset(void *s, int c, unsigned long n)
{
	unsigned char *p = s;
	unsigned long i;
	for (i = 0; i < n; i = i + 1)
		p[i] = (unsigned char) c;
	return s;
}
#endif

#ifndef QP_SVCOMP_OWN_memcmp
int memcmp(const void *s1, const void *s2, unsigned long n)
{
	const unsigned char *a = s1;
	const unsigned char *b = s2;
	unsigned long i;
	for (i = 0; i < n; i = i + 1)
		if (a[i] != b[i])
			return (int) a[i] - (int) b[i];
	return 0;
}
#endif

#ifndef QP_SVCOMP_OWN_memchr
void *memchr(const void *s, int c, unsigned long n)
{
	const unsigned char *p = s;
	unsigned long i;
	for (i = 0; i < n; i = i + 1)
		if (p[i] == (unsigned char) c)
			return (void *) (p + i);
	return (void *) 0;
}
#endif

#ifndef QP_SVCOMP_OWN_strlen
unsigned long strlen(const char *s)
{
	unsigned long i = 0;
	while (s[i] != 0)
		i = i + 1;
	return i;
}
#endif

#ifndef QP_SVCOMP_OWN_strnlen
unsigned long strnlen(const char *s, unsigned long n)
{
	unsigned long i = 0;
	while (i < n && s[i] != 0)
		i = i + 1;
	return i;
}
#endif

#ifndef QP_SVCOMP_OWN_strcmp
int strcmp(const char *a, const char *b)
{
	unsigned long i = 0;
	while (a[i] != 0 && a[i] == b[i])
		i = i + 1;
	return (int) (unsigned char) a[i] - (int) (unsigned char) b[i];
}
#endif

#ifndef QP_SVCOMP_OWN_strncmp
int strncmp(const char *a, const char *b, unsigned long n)
{
	unsigned long i = 0;
	while (i < n) {
		unsigned char x = (unsigned char) a[i];
		unsigned char y = (unsigned char) b[i];
		if (x != y)
			return (int) x - (int) y;
		if (x == 0)
			return 0;
		i = i + 1;
	}
	return 0;
}
#endif

#ifndef QP_SVCOMP_OWN_strchr
char *strchr(const char *s, int c)
{
	unsigned long i = 0;
	for (;;) {
		if (s[i] == (char) c)
			return (char *) (s + i);
		if (s[i] == 0)
			return (char *) 0;
		i = i + 1;
	}
}
#endif

#ifndef QP_SVCOMP_OWN_strrchr
char *strrchr(const char *s, int c)
{
	unsigned long i = 0;
	const char *last = (const char *) 0;
	for (;;) {
		if (s[i] == (char) c)
			last = s + i;
		if (s[i] == 0)
			return (char *) last;
		i = i + 1;
	}
}
#endif

#ifndef QP_SVCOMP_OWN_strcpy
char *strcpy(char *dest, const char *src)
{
	unsigned long i = 0;
	while (src[i] != 0) {
		dest[i] = src[i];
		i = i + 1;
	}
	dest[i] = 0;
	return dest;
}
#endif

#ifndef QP_SVCOMP_OWN_strncpy
char *strncpy(char *dest, const char *src, unsigned long n)
{
	unsigned long i = 0;
	while (i < n && src[i] != 0) {
		dest[i] = src[i];
		i = i + 1;
	}
	while (i < n) {
		dest[i] = 0;
		i = i + 1;
	}
	return dest;
}
#endif

#ifndef QP_SVCOMP_OWN_strcat
char *strcat(char *dest, const char *src)
{
	unsigned long d = 0, i = 0;
	while (dest[d] != 0)
		d = d + 1;
	while (src[i] != 0) {
		dest[d + i] = src[i];
		i = i + 1;
	}
	dest[d + i] = 0;
	return dest;
}
#endif

#ifndef QP_SVCOMP_OWN_strncat
char *strncat(char *dest, const char *src, unsigned long n)
{
	unsigned long d = 0, i = 0;
	while (dest[d] != 0)
		d = d + 1;
	while (i < n && src[i] != 0) {
		dest[d + i] = src[i];
		i = i + 1;
	}
	dest[d + i] = 0;
	return dest;
}
#endif

#ifndef QP_SVCOMP_OWN_strspn
unsigned long strspn(const char *s, const char *accept)
{
	unsigned long i = 0, j;
	for (;;) {
		if (s[i] == 0)
			return i;
		j = 0;
		while (accept[j] != 0 && accept[j] != s[i])
			j = j + 1;
		if (accept[j] == 0)
			return i;
		i = i + 1;
	}
}
#endif

#ifndef QP_SVCOMP_OWN_strcspn
unsigned long strcspn(const char *s, const char *reject)
{
	unsigned long i = 0, j;
	for (;;) {
		if (s[i] == 0)
			return i;
		j = 0;
		while (reject[j] != 0 && reject[j] != s[i])
			j = j + 1;
		if (reject[j] != 0)
			return i;
		i = i + 1;
	}
}
#endif

#ifndef QP_SVCOMP_OWN_strdup
char *strdup(const char *s)
{
	unsigned long n = 0, i;
	char *d;
	while (s[n] != 0)
		n = n + 1;
	d = malloc(n + 1);
	if (d == (char *) 0)
		return d;
	for (i = 0; i <= n; i = i + 1)
		d[i] = s[i];
	return d;
}
#endif

#ifndef QP_SVCOMP_OWN_abs
int abs(int x)
{
	return x < 0 ? -x : x;
}
#endif

#ifndef QP_SVCOMP_OWN_labs
long labs(long x)
{
	return x < 0 ? -x : x;
}
#endif

#endif /* __COMPCERT__ */
#endif /* QP_SVCOMP_LIBC_H */
