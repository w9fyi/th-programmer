/*
 * AMBE 3600x2450 Encoder — First open-source D-STAR AMBE encoder
 *
 * Transforms 160 samples of 8kHz 16-bit PCM into 9 bytes (72 bits) of AMBE.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES.
 */

#ifndef AMBE_ENCODE_H
#define AMBE_ENCODE_H

#include <stdint.h>

typedef struct {
    float prev_w0;           /* previous frame pitch (w0) */
    float prev_Ml[57];       /* previous frame log2 spectral amplitudes */
    float prev_gamma;        /* previous frame gamma (gain accumulator) */
    int   prev_L;            /* previous frame harmonic count */
    int   frame_count;       /* frame counter */
} ambe_encoder_state;

/* Initialize encoder state. Must be called before first encode. */
void ambe_encoder_init(ambe_encoder_state *state);

/* Encode one 20ms frame: 160 PCM samples (8kHz, 16-bit) -> 9 bytes AMBE. */
void ambe_encode_frame(ambe_encoder_state *state, const int16_t pcm[160], uint8_t ambe[9]);

#endif /* AMBE_ENCODE_H */
