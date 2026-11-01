/* recv_stub.c: a receive stub in the style of coreMQTT's network stubs (tests/qp/cbmc.sh). */
#include <stddef.h>
#include <stdint.h>

int32_t toy_recv(void *buf, size_t n)
{
	__CPROVER_assert(buf != NULL, "buf is not NULL");
	__CPROVER_assert(__CPROVER_w_ok(buf, n), "buf is writable up to n");
	__CPROVER_havoc_object(buf);
	return (int32_t) n;
}
