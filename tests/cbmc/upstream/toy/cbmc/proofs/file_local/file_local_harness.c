/* A static function of the library through __CPROVER_file_local_: refused. */
#include "toy_cbmc.h"

int __CPROVER_file_local_toy_c_toy_hidden(int x);

void harness(void)
{
	int x;
	(void) __CPROVER_file_local_toy_c_toy_hidden(x);
}
