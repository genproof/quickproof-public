/* A CBMC model of memcpy among the harness sources: replaced by the framework's plain-C memcpy. */
#include <stdlib.h>
#include <string.h>
#include "toy_cbmc.h"

void harness(void)
{
	uint8_t src[4];
	uint8_t dst[4];
	memcpy(dst, src, sizeof dst);
	__CPROVER_assert(memcmp(dst, src, 4) == 0, "copied");
}
