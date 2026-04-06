/*
 * AMBE 3600x2450 Encoder — Main orchestrator
 *
 * First open-source D-STAR AMBE encoder.
 * Transforms 160 samples of 8kHz 16-bit PCM into 9 bytes (72 bits).
 *
 * Pipeline:
 *   PCM[160] -> window -> pitch_est -> w0, L, b0
 *                      -> spectral_amplitudes -> Ml[1..L]
 *                      -> vuv_classify -> b1
 *                      -> quantize_spectral -> b2..b8
 *                      -> bitpack_encode -> 9 bytes
 */

#include <string.h>
#include <math.h>
#include "ambe_encode.h"
#include "pitch_est.h"
#include "spectral.h"
#include "vuv_classify.h"
#include "quantize.h"
#include "bitpack.h"
#include "fft_util.h"
#include "ambe_tables_extern.h"

void
ambe_encoder_init(ambe_encoder_state *state)
{
    memset(state, 0, sizeof(ambe_encoder_state));
    state->prev_w0 = 0.09378f;  /* Same as mbe_initMbeParms default */
    state->prev_L = 30;
    state->prev_gamma = 0.0f;
    state->frame_count = 0;
    /* prev_Ml initialized to 0 by memset (log2(1) = 0) */
}

void
ambe_encode_frame(ambe_encoder_state *state, const int16_t pcm[160], uint8_t ambe[9])
{
    int i;
    float pcm_float[160];
    float pcm_windowed[160];
    float window[160];
    float Ml[57];
    float cur_log2Ml[57];
    float w0;
    int L;
    int b0, b1, b2, b3, b4, b5, b6, b7, b8;
    float cur_gamma;
    float f0;

    /* Convert int16 PCM to float */
    for (i = 0; i < 160; i++) {
        pcm_float[i] = (float)pcm[i];
    }

    /* Apply Hamming window */
    hamming_window(window, 160);
    for (i = 0; i < 160; i++) {
        pcm_windowed[i] = pcm_float[i] * window[i];
    }

    /* Stage 1: Pitch estimation -> b0, w0, L */
    b0 = pitch_estimate(pcm_windowed, 160, &w0, &L);

    /* Check for silence/special frames */
    if (b0 >= 120) {
        /* Silence frame: b0=124, all other params zero-ish */
        bitpack_encode(b0, 0, 0, 0, 0, 0, 0, 0, 0, ambe);

        /* Update state for next frame */
        state->prev_w0 = 2.0f * (float)M_PI / 32.0f;
        state->prev_L = 14;
        state->prev_gamma = 0.0f;
        memset(state->prev_Ml, 0, sizeof(state->prev_Ml));
        state->frame_count++;
        return;
    }

    /* f0 for band assignment (AmbeW0table value, not w0 in radians) */
    f0 = AmbeW0table[b0];

    /* Stage 2: Spectral analysis -> Ml[1..L] */
    memset(Ml, 0, sizeof(Ml));
    spectral_amplitudes(pcm_windowed, 160, w0, L, Ml);

    /* Stage 3: V/UV classification -> b1 */
    b1 = vuv_classify(pcm_windowed, 160, w0, L, f0);

    /* Stage 4: Quantization -> b2..b8 */
    memset(cur_log2Ml, 0, sizeof(cur_log2Ml));
    quantize_spectral(Ml, L,
                      state->prev_gamma, state->prev_Ml, state->prev_L,
                      &b2, &b3, &b4, &b5, &b6, &b7, &b8,
                      &cur_gamma, cur_log2Ml);

    /* Stage 5: Bit pack + FEC + interleave -> 9 bytes */
    bitpack_encode(b0, b1, b2, b3, b4, b5, b6, b7, b8, ambe);

    /* Update state for next frame */
    state->prev_w0 = w0;
    state->prev_L = L;
    state->prev_gamma = cur_gamma;
    for (i = 0; i <= 56; i++) {
        state->prev_Ml[i] = cur_log2Ml[i];
    }
    state->frame_count++;
}
