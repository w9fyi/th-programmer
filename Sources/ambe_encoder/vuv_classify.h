/*
 * Voiced/Unvoiced classification for AMBE encoder
 */

#ifndef VUV_CLASSIFY_H
#define VUV_CLASSIFY_H

/*
 * Classify harmonics as voiced/unvoiced and find best b1 index.
 * pcm_windowed: Hamming-windowed PCM samples
 * num_samples: number of samples (160)
 * w0: fundamental frequency (radians)
 * L: number of harmonics
 * Returns b1 index (0..31) into AmbeVuv table.
 */
int vuv_classify(const float *pcm_windowed, int num_samples,
                 float w0, int L, float f0);

#endif /* VUV_CLASSIFY_H */
