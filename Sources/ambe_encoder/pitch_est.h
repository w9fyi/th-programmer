/*
 * Pitch estimation for AMBE encoder
 */

#ifndef PITCH_EST_H
#define PITCH_EST_H

/*
 * Estimate pitch from 160 PCM samples.
 * Returns b0 index (0..119) into AmbeW0table.
 * Sets *L to the number of harmonics from AmbeLtable[b0].
 * Sets *w0 to the fundamental frequency (radians).
 * Returns 124 (silence) if the frame energy is below threshold.
 */
int pitch_estimate(const float *pcm_windowed, int num_samples,
                   float *w0, int *L);

#endif /* PITCH_EST_H */
