/* memcpy_model.c: a CBMC model of memcpy (as in aws-c-common's stubs); replaced by the framework's libc. */
#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n)
{
	__CPROVER_precondition(__CPROVER_r_ok(src, n), "memcpy source region readable");
	__CPROVER_precondition(__CPROVER_w_ok(dst, n), "memcpy destination region writeable");
	__CPROVER_havoc_slice(dst, n);
	return dst;
}
