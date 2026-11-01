/* adler32.c: the Adler-32 checksum (RFC 1950), byte at a time (QuickProof quickstart example).
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
#include "adler32.h"

#define BASE 65521u     /* the largest prime below 65536 */

uint32_t adler32(uint32_t adler, const uint8_t *buf, size_t len)
{
	uint32_t a = adler & 0xffff, b = adler >> 16;
	for (size_t i = 0; i < len; i++) {
		a = (a + buf[i]) % BASE;
		b = (b + a) % BASE;
	}
	return (b << 16) | a;
}
