/*
 * Pitch estimation for AMBE 3600x2450 encoder
 *
 * Uses autocorrelation with parabolic interpolation to estimate
 * fundamental frequency, then quantizes to nearest AmbeW0table entry.
 */

#include <math.h>
#include <float.h>
#include "pitch_est.h"
#include "ambe_tables_extern.h"

/* Silence energy threshold — below this, emit silence frame */
#define SILENCE_THRESHOLD 50.0f

/* Lag search range: periods 20..148 samples
 * At 8kHz: period 20 = 400Hz, period 148 ~ 54Hz
 * This matches the AmbeW0table range:
 *   w0_max = AmbeW0table[0] * 2pi ~ 0.04997 * 2pi => period ~ 20
 *   w0_min = AmbeW0table[119] * 2pi ~ 0.00813 * 2pi => period ~ 123
 * We extend slightly to allow interpolation at boundaries.
 */
#define LAG_MIN 20
#define LAG_MAX 148

int
pitch_estimate(const float *pcm_windowed, int num_samples,
               float *w0, int *L)
{
    int i, lag;
    float energy = 0.0f;

    /* Compute frame energy to detect silence */
    for (i = 0; i < num_samples; i++) {
        energy += pcm_windowed[i] * pcm_windowed[i];
    }
    energy /= (float)num_samples;

    if (energy < SILENCE_THRESHOLD) {
        /* Silence frame: b0 = 124 */
        *w0 = 2.0f * (float)M_PI / 32.0f;
        *L = 14;
        return 124;
    }

    /* Autocorrelation at lag 0 */
    float r0 = 0.0f;
    for (i = 0; i < num_samples; i++) {
        r0 += pcm_windowed[i] * pcm_windowed[i];
    }

    if (r0 < 1e-10f) {
        *w0 = 2.0f * (float)M_PI / 32.0f;
        *L = 14;
        return 124;
    }

    /* Compute normalized autocorrelation for each lag */
    float best_corr = -1.0f;
    int best_lag = LAG_MIN;

    for (lag = LAG_MIN; lag <= LAG_MAX && lag < num_samples; lag++) {
        float sum = 0.0f;
        float energy_lag = 0.0f;
        for (i = 0; i < num_samples - lag; i++) {
            sum += pcm_windowed[i] * pcm_windowed[i + lag];
            energy_lag += pcm_windowed[i + lag] * pcm_windowed[i + lag];
        }
        float denom = sqrtf(r0 * energy_lag);
        float corr = (denom > 1e-10f) ? (sum / denom) : 0.0f;

        if (corr > best_corr) {
            best_corr = corr;
            best_lag = lag;
        }
    }

    /* Parabolic interpolation for sub-sample accuracy */
    float refined_lag = (float)best_lag;
    if (best_lag > LAG_MIN && best_lag < LAG_MAX && best_lag < num_samples - 1) {
        /* Compute autocorrelation at lag-1 and lag+1 */
        float rm1 = 0.0f, rp1 = 0.0f;
        for (i = 0; i < num_samples - best_lag - 1; i++) {
            rm1 += pcm_windowed[i] * pcm_windowed[i + best_lag - 1];
            rp1 += pcm_windowed[i] * pcm_windowed[i + best_lag + 1];
        }
        /* Add the extra sample for rm1 */
        rm1 += pcm_windowed[num_samples - best_lag - 1] * pcm_windowed[num_samples - 2];

        float denom = rm1 - 2.0f * best_corr * sqrtf(r0) + rp1;
        /* Only interpolate if we get a reasonable denominator */
        if (fabsf(denom) > 1e-10f) {
            float delta = 0.5f * (rm1 - rp1) / denom;
            if (delta > -1.0f && delta < 1.0f) {
                refined_lag = (float)best_lag + delta;
            }
        }
    }

    /* Convert lag to f0 (cycles per sample), then to w0 */
    float f0 = 1.0f / refined_lag;
    float w0_est = f0;  /* AmbeW0table stores f0, not w0 */

    /* Find nearest entry in AmbeW0table[0..119] */
    float best_dist = FLT_MAX;
    int b0 = 0;
    for (i = 0; i < 120; i++) {
        float dist = fabsf(AmbeW0table[i] - w0_est);
        if (dist < best_dist) {
            best_dist = dist;
            b0 = i;
        }
    }

    /* Look up L from AmbeLtable */
    *w0 = AmbeW0table[b0] * 2.0f * (float)M_PI;
    *L = (int)AmbeLtable[b0];

    return b0;
}
