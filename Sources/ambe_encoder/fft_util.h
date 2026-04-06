/*
 * FFT utilities for AMBE encoder
 */

#ifndef FFT_UTIL_H
#define FFT_UTIL_H

#define FFT_SIZE 256

/* In-place radix-2 DIT FFT. real[FFT_SIZE] and imag[FFT_SIZE]. */
void fft_radix2(float *real, float *imag, int n);

/* Generate Hamming window of given length into out[]. */
void hamming_window(float *out, int length);

#endif /* FFT_UTIL_H */
