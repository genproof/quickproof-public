/* rle.c: a tiny run-length codec (QuickProof quickstart example).  SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
#include "rle.h"

size_t rle_decode(const uint8_t *in, size_t n, uint8_t *out, size_t cap)
{
	size_t i = 0, m = 0;
	while (n - i >= 2) {
		size_t count = in[i];
		uint8_t byte = in[i + 1];
		if (count > cap - m)
			return 0;
		for (size_t k = 0; k < count; k++)
			out[m + k] = byte;
		m += count;
		i += 2;
	}
	return m;
}
