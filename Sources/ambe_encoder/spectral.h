/*
 * Spectral analysis for AMBE encoder
 */

#ifndef SPECTRAL_H
#define SPECTRAL_H

/*
 * Extract harmonic amplitudes from windowed PCM.
 * w0: fundamental frequency in radians (2*pi*f0)
 * L: number of harmonics
 * Ml[1..L]: output spectral amplitudes (index 0 unused)
 */
void spectral_amplitudes(const float *pcm_windowed, int num_samples,
                         float w0, int L, float *Ml);

#endif /* SPECTRAL_H */
