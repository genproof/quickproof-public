/* adler32.h: the Adler-32 checksum (QuickProof quickstart example).  SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
#ifndef ADLER32_H
#define ADLER32_H
#include <stddef.h>
#include <stdint.h>

/* adler32: updates the running checksum `adler` with buf[0..len-1] and returns the new checksum.  Start with
 * adler = 1; a long message may be checksummed piece by piece. */
uint32_t adler32(uint32_t adler, const uint8_t *buf, size_t len);

#endif
