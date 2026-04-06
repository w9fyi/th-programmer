/*
 * FFT utilities for AMBE encoder
 * Simple radix-2 DIT FFT — no external dependencies needed.
 */

#include <math.h>
#include "fft_util.h"

void
hamming_window(float *out, int length)
{
    for (int i = 0; i < length; i++) {
        out[i] = 0.54f - 0.46f * cosf(2.0f * (float)M_PI * (float)i / (float)(length - 1));
    }
}

/*
 * In-place radix-2 decimation-in-time FFT.
 * n must be a power of 2.
 */
void
fft_radix2(float *real, float *imag, int n)
{
    /* Bit-reversal permutation */
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
        if (i < j) {
            float tr = real[j]; real[j] = real[i]; real[i] = tr;
            float ti = imag[j]; imag[j] = imag[i]; imag[i] = ti;
        }
        int k = n >> 1;
        while (k <= j) {
            j -= k;
            k >>= 1;
        }
        j += k;
    }

    /* Butterfly stages */
    for (int stage = 1; stage < n; stage <<= 1) {
        float angle = -(float)M_PI / (float)stage;
        float wpr = cosf(angle);
        float wpi = sinf(angle);

        for (int group = 0; group < n; group += stage << 1) {
            float wr = 1.0f, wi = 0.0f;
            for (int pair = 0; pair < stage; pair++) {
                int a = group + pair;
                int b = a + stage;
                float tr = wr * real[b] - wi * imag[b];
                float ti = wr * imag[b] + wi * real[b];
                real[b] = real[a] - tr;
                imag[b] = imag[a] - ti;
                real[a] += tr;
                imag[a] += ti;
                float wnr = wr * wpr - wi * wpi;
                float wni = wr * wpi + wi * wpr;
                wr = wnr;
                wi = wni;
            }
        }
    }
}
