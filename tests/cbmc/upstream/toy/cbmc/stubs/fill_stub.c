/* fill_stub.c: a stub that checks and havocs a slice (tests/qp/cbmc.sh). */
#include <stddef.h>
#include <stdint.h>

int32_t toy_fill(void *buf, size_t n)
{
	__CPROVER_assert(__CPROVER_w_ok(buf, n), "buf is writable up to n");
	__CPROVER_havoc_slice(buf, n);
	return (int32_t) n;
}
