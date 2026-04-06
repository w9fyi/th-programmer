/*
 * Spectral analysis for AMBE 3600x2450 encoder
 *
 * Extracts harmonic amplitudes using DFT at each harmonic frequency.
 * Uses a small DFT bin interpolation around each harmonic peak.
 */

#include <math.h>
#include "spectral.h"
#include "fft_util.h"

void
spectral_amplitudes(const float *pcm_windowed, int num_samples,
                    float w0, int L, float *Ml)
{
    int k, n;

    /*
     * For each harmonic k (1..L), compute the DFT magnitude at
     * frequency k*w0 using direct DFT evaluation.
     * This is more accurate than FFT bin lookup for arbitrary frequencies.
     *
     * X(omega) = sum_{n=0}^{N-1} x[n] * e^{-j*omega*n}
     * |X(omega)| = sqrt(Re^2 + Im^2)
     */
    for (k = 1; k <= L; k++) {
        float freq = (float)k * w0;  /* w0 is already in radians */
        float re = 0.0f, im = 0.0f;

        for (n = 0; n < num_samples; n++) {
            float angle = freq * (float)n;
            re += pcm_windowed[n] * cosf(angle);
            im -= pcm_windowed[n] * sinf(angle);
        }

        float mag = sqrtf(re * re + im * im);

        /* Normalize by window length to get amplitude estimate */
        Ml[k] = mag / (float)num_samples;

        /* Floor to prevent log2(0) issues downstream */
        if (Ml[k] < 1e-6f) {
            Ml[k] = 1e-6f;
        }
    }
}
