/* Harness code that CBMC accepts but a C compiler rejects (a stub declared with a misspelled struct tag,
 * as in coreMQTT's EventCallbackStub): refused, with the compiler's message. */
#include "toy_cbmc.h"

void stub(struct toy_bfu *b);

void stub(struct toy_buf *b)
{
	(void) b;
}

void harness(void)
{
}
