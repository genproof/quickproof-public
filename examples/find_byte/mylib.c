/* mylib.c: find_byte, a small library to replace by your own (QuickProof example).
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
#include "mylib.h"

size_t find_byte(const uint8_t *buf, size_t n, uint8_t c)
{
	size_t i = 0;
	while (i < n && buf[i] != c)
		i++;
	return i;
}
