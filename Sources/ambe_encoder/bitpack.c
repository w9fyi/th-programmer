/*
 * Bit packing, FEC encoding, and interleaving for AMBE 3600x2450 encoder.
 *
 * This is the exact inverse of the decoder pipeline:
 *   mbe_decodeAmbe2450Parms (bit extraction) <- we pack bits
 *   mbe_eccAmbe3600x2450Data (Golay/Hamming decode) <- we encode FEC
 *   mbe_demodulateAmbe3600x2450Data (PRNG XOR) <- we modulate
 *   deinterleaveAmbe3600x2450 (dW/dX unpack) <- we interleave
 *
 * Bit positions extracted from mbe_decodeAmbe2450Parms():
 *
 *   b0 (7 bits): d[0]<<6 | d[1]<<5 | d[2]<<4 | d[3]<<3 | d[37]<<2 | d[38]<<1 | d[39]
 *   b1 (5 bits): d[4]<<4 | d[5]<<3 | d[6]<<2 | d[7]<<1 | d[35]
 *   b2 (5 bits): d[8]<<4 | d[9]<<3 | d[10]<<2 | d[11]<<1 | d[36]
 *   b3 (9 bits): d[12]<<8 | d[13]<<7 | d[14]<<6 | d[15]<<5 | d[16]<<4 | d[17]<<3 | d[18]<<2 | d[19]<<1 | d[40]
 *   b4 (7 bits): d[20]<<6 | d[21]<<5 | d[22]<<4 | d[23]<<3 | d[41]<<2 | d[42]<<1 | d[43]
 *   b5 (5 bits): d[24]<<4 | d[25]<<3 | d[26]<<2 | d[27]<<1 | d[44]
 *   b6 (4 bits): d[28]<<3 | d[29]<<2 | d[30]<<1 | d[45]
 *   b7 (4 bits): d[31]<<3 | d[32]<<2 | d[33]<<1 | d[46]
 *   b8 (3 bits): d[34]<<2 | d[47]<<1 | d[48]
 *
 * Total: 7+5+5+9+7+5+4+4+3 = 49 bits
 */

#include <string.h>
#include "bitpack.h"
#include "ambe_tables_extern.h"

/*
 * dW and dX interleave tables from DSD / AMBECodec.swift.
 * dW[i] = row (0..3), dX[i] = column in ambe_fr[row][col].
 * For DEinterleaving (decode): bit i of serial stream -> ambe_fr[dW[i]][dX[i]]
 * For INTERLEAVING (encode): ambe_fr[dW[i]][dX[i]] -> bit i of serial stream
 */
static const int dW[72] = {
    0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
    3, 2, 1, 1, 3, 2, 1, 1, 0, 0, 3, 2,
    0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
    3, 2, 1, 1, 3, 2, 1, 1, 0, 0, 3, 2,
    0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
    3, 2, 1, 1, 3, 3, 2, 1, 0, 0, 3, 3
};

static const int dX[72] = {
    10, 22, 11,  9, 10, 22, 11, 23,  8, 20,  9, 21,
    10,  8,  9, 21,  8,  6,  7, 19,  8, 20,  9,  7,
     6, 18,  7,  5,  6, 18,  7, 19,  4, 16,  5, 17,
     6,  4,  5, 17,  4,  2,  3, 15,  4, 16,  5,  3,
     2, 14,  3,  1,  2, 14,  3, 15,  0, 12,  1, 13,
     2,  0,  1, 13,  0, 12, 10, 11,  0, 12,  1, 13
};

/*
 * Pack parameter indices into 49-bit ambe_d array.
 * Each element is a single bit (0 or 1).
 */
static void pack_params(int b0, int b1, int b2, int b3, int b4,
                         int b5, int b6, int b7, int b8,
                         char ambe_d[49])
{
    memset(ambe_d, 0, 49);

    /* b0: 7 bits */
    ambe_d[0]  = (b0 >> 6) & 1;
    ambe_d[1]  = (b0 >> 5) & 1;
    ambe_d[2]  = (b0 >> 4) & 1;
    ambe_d[3]  = (b0 >> 3) & 1;
    ambe_d[37] = (b0 >> 2) & 1;
    ambe_d[38] = (b0 >> 1) & 1;
    ambe_d[39] = (b0 >> 0) & 1;

    /* b1: 5 bits */
    ambe_d[4]  = (b1 >> 4) & 1;
    ambe_d[5]  = (b1 >> 3) & 1;
    ambe_d[6]  = (b1 >> 2) & 1;
    ambe_d[7]  = (b1 >> 1) & 1;
    ambe_d[35] = (b1 >> 0) & 1;

    /* b2: 5 bits */
    ambe_d[8]  = (b2 >> 4) & 1;
    ambe_d[9]  = (b2 >> 3) & 1;
    ambe_d[10] = (b2 >> 2) & 1;
    ambe_d[11] = (b2 >> 1) & 1;
    ambe_d[36] = (b2 >> 0) & 1;

    /* b3: 9 bits */
    ambe_d[12] = (b3 >> 8) & 1;
    ambe_d[13] = (b3 >> 7) & 1;
    ambe_d[14] = (b3 >> 6) & 1;
    ambe_d[15] = (b3 >> 5) & 1;
    ambe_d[16] = (b3 >> 4) & 1;
    ambe_d[17] = (b3 >> 3) & 1;
    ambe_d[18] = (b3 >> 2) & 1;
    ambe_d[19] = (b3 >> 1) & 1;
    ambe_d[40] = (b3 >> 0) & 1;

    /* b4: 7 bits */
    ambe_d[20] = (b4 >> 6) & 1;
    ambe_d[21] = (b4 >> 5) & 1;
    ambe_d[22] = (b4 >> 4) & 1;
    ambe_d[23] = (b4 >> 3) & 1;
    ambe_d[41] = (b4 >> 2) & 1;
    ambe_d[42] = (b4 >> 1) & 1;
    ambe_d[43] = (b4 >> 0) & 1;

    /* b5: 5 bits */
    ambe_d[24] = (b5 >> 4) & 1;
    ambe_d[25] = (b5 >> 3) & 1;
    ambe_d[26] = (b5 >> 2) & 1;
    ambe_d[27] = (b5 >> 1) & 1;
    ambe_d[44] = (b5 >> 0) & 1;

    /* b6: 4 bits */
    ambe_d[28] = (b6 >> 3) & 1;
    ambe_d[29] = (b6 >> 2) & 1;
    ambe_d[30] = (b6 >> 1) & 1;
    ambe_d[45] = (b6 >> 0) & 1;

    /* b7: 4 bits */
    ambe_d[31] = (b7 >> 3) & 1;
    ambe_d[32] = (b7 >> 2) & 1;
    ambe_d[33] = (b7 >> 1) & 1;
    ambe_d[46] = (b7 >> 0) & 1;

    /* b8: 3 bits */
    ambe_d[34] = (b8 >> 2) & 1;
    ambe_d[47] = (b8 >> 1) & 1;
    ambe_d[48] = (b8 >> 0) & 1;
}

/*
 * Distribute 49 data bits into the ambe_fr[4][24] frame matrix.
 * This is the exact reverse of mbe_eccAmbe3600x2450Data().
 *
 * The decoder copies bits from ambe_fr into ambe_d as follows:
 *   C0 (ambe_fr[0]): 12 data bits -> ambe_d[0..11]
 *     for j=23 down to 12: ambe_d[pos++] = ambe_fr[0][j]
 *
 *   C1 (ambe_fr[1]): 12 data bits -> ambe_d[12..23]
 *     Golay decoded, then for j=22 down to 11: ambe_d[pos++] = gout[j]
 *
 *   C2 (ambe_fr[2]): 11 bits -> ambe_d[24..34]
 *     for j=10 down to 0: ambe_d[pos++] = ambe_fr[2][j]
 *
 *   C3 (ambe_fr[3]): 14 bits -> ambe_d[35..48]
 *     for j=13 down to 0: ambe_d[pos++] = ambe_fr[3][j]
 */
static void distribute_to_fr(const char ambe_d[49], char ambe_fr[4][24])
{
    int pos, j;

    memset(ambe_fr, 0, 4 * 24);

    /* C0: ambe_d[0..11] -> ambe_fr[0][23..12] */
    pos = 0;
    for (j = 23; j >= 12; j--) {
        ambe_fr[0][j] = ambe_d[pos++];
    }
    /* pos is now 12 */

    /* C1: ambe_d[12..23] -> ambe_fr[1][22..11] (data bits only, before Golay) */
    for (j = 22; j >= 11; j--) {
        ambe_fr[1][j] = ambe_d[pos++];
    }
    /* pos is now 24 */

    /* C2: ambe_d[24..34] -> ambe_fr[2][10..0] */
    for (j = 10; j >= 0; j--) {
        ambe_fr[2][j] = ambe_d[pos++];
    }
    /* pos is now 35 */

    /* C3: ambe_d[35..48] -> ambe_fr[3][13..0] */
    for (j = 13; j >= 0; j--) {
        ambe_fr[3][j] = ambe_d[pos++];
    }
    /* pos is now 49 */
}

/*
 * Golay(23,12) encode for C0 block.
 * Uses golayGenerator[12] from ecc_const.h.
 * Input: 12 data bits in ambe_fr[0][23..12]
 * Output: 11 parity bits placed in ambe_fr[0][10..0], plus parity bit in [11]
 *
 * The Golay(24,12) code: 12 data bits produce 12 parity bits (11 Golay + 1 overall).
 * ambe_fr[0][0] is the overall parity bit.
 * ambe_fr[0][1..11] are the 11 Golay parity bits.
 * ambe_fr[0][12..23] are the 12 data bits.
 */
static void golay_encode_c0(char ambe_fr[4][24])
{
    int i, j;
    unsigned int parity = 0;

    /* Extract 12 data bits (ambe_fr[0][12..23]) */
    for (i = 0; i < 12; i++) {
        if (ambe_fr[0][i + 12]) {
            parity ^= (unsigned int)golayGenerator[i];
        }
    }

    /* Place 11 parity bits in ambe_fr[0][1..11] */
    for (j = 0; j < 11; j++) {
        ambe_fr[0][j + 1] = (parity >> j) & 1;
    }

    /* Compute overall parity bit (ambe_fr[0][0]) */
    int total = 0;
    for (j = 1; j <= 23; j++) {
        total ^= ambe_fr[0][j];
    }
    ambe_fr[0][0] = total;
}

/*
 * Golay(23,12) encode for C1 block.
 * Input: 12 data bits in ambe_fr[1][22..11]
 * Output: 11 parity bits placed in ambe_fr[1][10..0]
 */
static void golay_encode_c1(char ambe_fr[4][24])
{
    int i, j;
    unsigned int parity = 0;

    /* The Golay encoder uses bits [11..22] as 12 data bits.
     * golayGenerator maps bit positions: for each data bit that is 1,
     * XOR the corresponding generator word into parity.
     * In mbe_golay2312, the input is packed as in[22..0] where
     * in[22..11] are data and in[10..0] are parity.
     * The generator is applied to bits [22..11] (12 data bits).
     */
    for (i = 0; i < 12; i++) {
        if (ambe_fr[1][i + 11]) {
            parity ^= (unsigned int)golayGenerator[i];
        }
    }

    /* Place 11 parity bits in ambe_fr[1][0..10] */
    for (j = 0; j < 11; j++) {
        ambe_fr[1][j] = (parity >> j) & 1;
    }
}

/*
 * PRNG modulation (same as mbe_demodulateAmbe3600x2450Data but applied forward).
 *
 * The pseudo-random sequence is derived from C0 data bits (ambe_fr[0][23..12]).
 * XOR it with C1 bits. For encoding, we must apply this AFTER placing C1 data
 * bits and C1 FEC bits, so the decoder's XOR (demodulate) will undo it.
 */
static void prng_modulate(char ambe_fr[4][24])
{
    int i, j, k;
    unsigned short pr[25];
    unsigned short foo = 0;

    /* Create seed from C0 data bits (ambe_fr[0][23..12]) — same as decoder */
    for (i = 23; i >= 12; i--) {
        foo <<= 1;
        foo |= (unsigned short)ambe_fr[0][i];
    }
    pr[0] = (unsigned short)(16 * foo);
    for (i = 1; i < 24; i++) {
        pr[i] = (unsigned short)((173 * pr[i - 1]) + 13849 -
                (65536 * (((173 * pr[i - 1]) + 13849) / 65536)));
    }
    for (i = 1; i < 24; i++) {
        pr[i] = (unsigned short)(pr[i] / 32768);
    }

    /* XOR C1 bits with PR sequence — same operation as decoder (XOR is its own inverse) */
    k = 1;
    for (j = 22; j >= 0; j--) {
        ambe_fr[1][j] = (char)((ambe_fr[1][j]) ^ pr[k]);
        k++;
    }
}

/*
 * Interleave ambe_fr[4][24] into 9 bytes (72 bits).
 * This is the reverse of the deinterleave operation in AMBECodec.swift.
 * For each serial bit position i (0..71):
 *   byte[i/8] bit (i%8) = ambe_fr[dW[i]][dX[i]]
 * Uses LSB-first bit packing (D-STAR convention).
 */
static void interleave_to_bytes(const char ambe_fr[4][24], unsigned char ambe_out[9])
{
    int i;
    memset(ambe_out, 0, 9);

    for (i = 0; i < 72; i++) {
        int row = dW[i];
        int col = dX[i];
        if (ambe_fr[row][col]) {
            int byteIdx = i / 8;
            int bitIdx  = i % 8;  /* LSB-first */
            ambe_out[byteIdx] |= (unsigned char)(1 << bitIdx);
        }
    }
}

void
bitpack_encode(int b0, int b1, int b2, int b3, int b4,
               int b5, int b6, int b7, int b8,
               uint8_t ambe_out[9])
{
    char ambe_d[49];
    char ambe_fr[4][24];

    /* Step 1: Pack parameter indices into 49 data bits */
    pack_params(b0, b1, b2, b3, b4, b5, b6, b7, b8, ambe_d);

    /* Step 2: Distribute data bits into ambe_fr[4][24] */
    distribute_to_fr(ambe_d, ambe_fr);

    /* Step 3: Golay encode C0 (24,12) — adds parity bits to ambe_fr[0][0..11] */
    golay_encode_c0(ambe_fr);

    /* Step 4: Golay encode C1 (23,12) — adds parity bits to ambe_fr[1][0..10] */
    golay_encode_c1(ambe_fr);

    /* Step 5: PRNG modulation of C1 (must be after FEC encoding) */
    prng_modulate(ambe_fr);

    /* Step 6: Interleave and serialize to 9 bytes */
    interleave_to_bytes(ambe_fr, ambe_out);
}
