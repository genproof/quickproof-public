/* rle.h: a tiny run-length codec (QuickProof quickstart example).  SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
#ifndef RLE_H
#define RLE_H
#include <stddef.h>
#include <stdint.h>

/* rle_decode: the input is a sequence of pairs (count, byte), each meaning `count` copies of `byte`; a last
 * odd byte is ignored.  Writes the decoded bytes to out[0..cap-1] and returns how many it wrote, or 0 when
 * they do not fit in `cap` bytes. */
size_t rle_decode(const uint8_t *in, size_t n, uint8_t *out, size_t cap);

#endif
