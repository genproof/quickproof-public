/* mylib.h: find_byte, a small library to replace by your own (QuickProof example).
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
#ifndef MYLIB_H
#define MYLIB_H
#include <stddef.h>
#include <stdint.h>

/* find_byte: the index of the first byte equal to c in buf[0..n-1], or n when there is none. */
size_t find_byte(const uint8_t *buf, size_t n, uint8_t c);

#endif
