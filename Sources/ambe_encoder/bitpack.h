/*
 * Bit packing, FEC encoding, and interleaving for AMBE encoder
 */

#ifndef BITPACK_H
#define BITPACK_H

#include <stdint.h>

/*
 * Pack b0..b8 parameter indices into 49 data bits,
 * apply FEC (Golay + PRNG modulation), interleave,
 * and serialize into 9 output bytes.
 *
 * b0: 7-bit pitch index (0..119, or 124/125 for silence)
 * b1: 5-bit V/UV index
 * b2: 5-bit gain index
 * b3: 9-bit PRBA24 index
 * b4: 7-bit PRBA58 index
 * b5: 5-bit HOCb5 index
 * b6: 4-bit HOCb6 index
 * b7: 4-bit HOCb7 index
 * b8: 3-bit HOCb8 index
 * ambe_out: 9-byte output buffer
 */
void bitpack_encode(int b0, int b1, int b2, int b3, int b4,
                    int b5, int b6, int b7, int b8,
                    uint8_t ambe_out[9]);

#endif /* BITPACK_H */
