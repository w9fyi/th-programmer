/*
 * Voiced/Unvoiced classification for AMBE 3600x2450 encoder
 *
 * Divides harmonics into 8 frequency bands and computes a
 * harmonicity metric for each band. Finds best matching V/UV
 * pattern in AmbeVuv[32][8].
 */

#include <math.h>
#include "vuv_classify.h"
#include "ambe_tables_extern.h"

/*
 * The decoder maps harmonic l to band j using:
 *   jl = (int)(l * 16.0 * f0)
 * where f0 = AmbeW0table[b0] and jl is in range [0..7].
 *
 * For encoding, we evaluate each harmonic's band assignment,
 * compute a per-band voiced/unvoiced decision, then find the
 * closest AmbeVuv pattern.
 */

/* Harmonicity threshold: above this ratio = voiced */
#define VUV_THRESHOLD 0.6f

int
vuv_classify(const float *pcm_windowed, int num_samples,
             float w0, int L, float f0)
{
    int l, j, b1;
    int band_voiced[8];
    float band_harmonic_energy[8];
    float band_total_energy[8];

    /* Initialize band accumulators */
    for (j = 0; j < 8; j++) {
        band_harmonic_energy[j] = 0.0f;
        band_total_energy[j] = 0.0f;
        band_voiced[j] = 0;
    }

    /*
     * For each harmonic, compute the energy at the harmonic frequency
     * vs the energy in a band around it. A high ratio means the energy
     * is concentrated at the harmonic = voiced.
     */
    for (l = 1; l <= L; l++) {
        /* Band assignment — same formula as decoder */
        int jl = (int)((float)l * 16.0f * f0);
        if (jl > 7) jl = 7;
        if (jl < 0) jl = 0;

        /* Compute DFT magnitude at harmonic frequency */
        float freq = (float)l * w0;
        float re = 0.0f, im = 0.0f;
        for (int n = 0; n < num_samples; n++) {
            float angle = freq * (float)n;
            re += pcm_windowed[n] * cosf(angle);
            im -= pcm_windowed[n] * sinf(angle);
        }
        float harmonic_power = re * re + im * im;

        /* Compute energy in a small band around the harmonic
         * (evaluate at +/- 0.25*w0 offsets) */
        float total_power = harmonic_power;
        float offsets[2] = { -0.25f * w0, 0.25f * w0 };
        for (int oi = 0; oi < 2; oi++) {
            float foff = freq + offsets[oi];
            float ore = 0.0f, oim = 0.0f;
            for (int n = 0; n < num_samples; n++) {
                float angle = foff * (float)n;
                ore += pcm_windowed[n] * cosf(angle);
                oim -= pcm_windowed[n] * sinf(angle);
            }
            total_power += ore * ore + oim * oim;
        }

        band_harmonic_energy[jl] += harmonic_power;
        band_total_energy[jl] += total_power;
    }

    /* Decide voiced/unvoiced per band */
    for (j = 0; j < 8; j++) {
        if (band_total_energy[j] > 1e-10f) {
            float ratio = band_harmonic_energy[j] / band_total_energy[j];
            band_voiced[j] = (ratio > VUV_THRESHOLD) ? 1 : 0;
        } else {
            band_voiced[j] = 0;
        }
    }

    /* Find best matching AmbeVuv pattern (minimum Hamming distance) */
    int best_dist = 9;
    b1 = 16;  /* default: all unvoiced */
    for (int idx = 0; idx < 32; idx++) {
        int dist = 0;
        for (j = 0; j < 8; j++) {
            if (AmbeVuv[idx][j] != band_voiced[j]) {
                dist++;
            }
        }
        if (dist < best_dist) {
            best_dist = dist;
            b1 = idx;
        }
    }

    return b1;
}
