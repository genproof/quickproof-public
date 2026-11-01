/* mylib.c: your library.  Replace this example with your own code. */
#include "mylib.h"

size_t count_byte(const uint8_t *buf, size_t n, uint8_t c)
{
	size_t k = 0;
	for (size_t i = 0; i < n; i++)
		if (buf[i] == c)
			k++;
	return k;
}
