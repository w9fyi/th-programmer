/*
 * Quantization for AMBE encoder — gain, PRBA, HOC VQ
 */

#ifndef QUANTIZE_H
#define QUANTIZE_H

/*
 * Quantize spectral amplitudes into AMBE parameter indices.
 *
 * Ml[1..L]: spectral amplitudes (linear)
 * L: harmonic count
 * prev_gamma: previous frame gamma accumulator
 * prev_log2Ml[0..56]: previous frame log2 amplitudes
 * prev_L: previous frame harmonic count
 *
 * Outputs: b2..b8 indices, cur_gamma (updated gamma)
 */
void quantize_spectral(const float *Ml, int L,
                       float prev_gamma, const float *prev_log2Ml, int prev_L,
                       int *b2, int *b3, int *b4,
                       int *b5, int *b6, int *b7, int *b8,
                       float *cur_gamma,
                       float *cur_log2Ml);

#endif /* QUANTIZE_H */
