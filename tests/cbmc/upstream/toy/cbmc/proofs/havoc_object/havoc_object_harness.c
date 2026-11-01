/* __CPROVER_havoc_object in a stub: refused (the object size is not known in C). */
#include <stdlib.h>
#include "toy_cbmc.h"

int32_t toy_recv(void *buf, size_t n);

void harness(void)
{
	uint8_t buf[4];
	(void) toy_recv(buf, sizeof buf);
}
