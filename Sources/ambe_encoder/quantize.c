/*
 * Quantization for AMBE 3600x2450 encoder
 *
 * Performs the inverse of the decoder's parameter reconstruction:
 * - Compute log2 spectral amplitudes
 * - Compute gain (gamma) with delta coding from previous frame
 * - Forward DCT to get PRBA coefficients
 * - Vector quantize PRBA and higher-order coefficients
 *
 * The decoder (mbe_decodeAmbe2450Parms) reconstructs amplitudes via:
 *   1. Inverse DCT of Cik -> Tl (residual)
 *   2. log2Ml[l] = Tl[l] + 0.65*(interp prev) - Sum43 + BigGamma
 *   3. BigGamma = gamma - 0.5*log2(L) - mean(Tl)
 *   4. gamma = deltaGamma + 0.5*prev_gamma
 *
 * For encoding, we reverse this: given current log2Ml and prev state,
 * solve for Tl, then forward DCT to get Cik, then VQ to get indices.
 */

#include <math.h>
#include <float.h>
#include <string.h>
#include "quantize.h"
#include "ambe_tables_extern.h"

/* log2(x) = log(x) / log(2) */
static float log2f_safe(float x)
{
    if (x < 1e-10f) x = 1e-10f;
    return logf(x) / logf(2.0f);
}

/*
 * Forward DCT (Type-II, same basis as decoder's inverse)
 * The decoder uses inverse DCT:
 *   Tl[j] = sum_{k=1}^{Ji} ak * Cik[k] * cos(pi*(k-1)*(j-0.5)/Ji)
 * where ak = 1 for k=1, 2 for k>1.
 *
 * The forward DCT to recover Cik from Tl:
 *   Cik[k] = (2/Ji) * sum_{j=1}^{Ji} Tl[j] * cos(pi*(k-1)*(j-0.5)/Ji)
 * with Cik[1] *= 0.5 (DC normalization).
 */
static void forward_dct(const float *Tl, int Ji, float *Cik)
{
    for (int k = 1; k <= Ji && k <= 6; k++) {
        float sum = 0.0f;
        for (int j = 1; j <= Ji; j++) {
            sum += Tl[j] * cosf((float)M_PI * (float)(k - 1) *
                                ((float)j - 0.5f) / (float)Ji);
        }
        Cik[k] = (2.0f / (float)Ji) * sum;
        if (k == 1) {
            Cik[k] *= 0.5f;  /* DC term normalization */
        }
    }
}

/*
 * Euclidean distance between two float vectors.
 */
static float vq_dist(const float *a, const float *b, int len)
{
    float sum = 0.0f;
    for (int i = 0; i < len; i++) {
        float d = a[i] - b[i];
        sum += d * d;
    }
    return sum;
}

void
quantize_spectral(const float *Ml, int L,
                  float prev_gamma, const float *prev_log2Ml, int prev_L,
                  int *b2, int *b3, int *b4,
                  int *b5, int *b6, int *b7, int *b8,
                  float *cur_gamma,
                  float *cur_log2Ml)
{
    int l, i, m;
    float log2Ml_local[57];
    float Tl[57];
    float Sum43, Sum42, BigGamma;
    float flokl[57], deltal[57];
    int intkl[57];

    /* Step 1: Compute log2 of spectral amplitudes */
    for (l = 1; l <= L; l++) {
        log2Ml_local[l] = log2f_safe(Ml[l]);
        cur_log2Ml[l] = log2Ml_local[l];
    }
    /* Copy endpoint for interpolation */
    cur_log2Ml[0] = cur_log2Ml[1];

    /*
     * Step 2: Compute the prediction from previous frame (same as decoder)
     * We need to compute Sum43 and the interpolated prev values,
     * then solve for Tl = log2Ml - interpolated_prev - BigGamma + Sum43
     */

    /* Handle L change: extend previous frame if needed */
    float prev_log2Ml_ext[58];
    memset(prev_log2Ml_ext, 0, sizeof(prev_log2Ml_ext));
    for (l = 0; l <= 56; l++) {
        prev_log2Ml_ext[l] = prev_log2Ml[l];
    }
    if (L > prev_L && prev_L > 0) {
        for (l = prev_L + 1; l <= L; l++) {
            prev_log2Ml_ext[l] = prev_log2Ml_ext[prev_L];
        }
    }
    prev_log2Ml_ext[0] = prev_log2Ml_ext[1];

    /* Compute interpolation indices (eq. 40-41 from decoder) */
    int prev_L_safe = (prev_L > 0) ? prev_L : 1;
    for (l = 1; l <= L; l++) {
        flokl[l] = ((float)prev_L_safe / (float)L) * (float)l;
        intkl[l] = (int)flokl[l];
        if (intkl[l] < 0) intkl[l] = 0;
        if (intkl[l] > 56) intkl[l] = 56;
        deltal[l] = flokl[l] - (float)intkl[l];
    }

    /* Compute Sum43 (eq. 43) */
    Sum43 = 0.0f;
    for (l = 1; l <= L; l++) {
        int idx = intkl[l];
        int idx1 = idx + 1;
        if (idx1 > 56) idx1 = 56;
        Sum43 += ((1.0f - deltal[l]) * prev_log2Ml_ext[idx]) +
                 (deltal[l] * prev_log2Ml_ext[idx1]);
    }
    Sum43 = (0.65f / (float)L) * Sum43;

    /*
     * Step 3: Compute Tl (residual) — we need to solve:
     *   log2Ml[l] = Tl[l] + c1 + c2 - Sum43 + BigGamma
     * where:
     *   c1 = 0.65 * (1-delta) * prev_log2Ml[intk]
     *   c2 = 0.65 * delta * prev_log2Ml[intk+1]
     *   BigGamma = gamma - 0.5*log2(L) - mean(Tl)
     *   gamma = deltaGamma + 0.5*prev_gamma
     *
     * This is circular (Tl depends on BigGamma which depends on mean(Tl)).
     * Solve by first computing the prediction residual without BigGamma,
     * then extracting BigGamma as the mean.
     */

    /* Compute raw residual (before BigGamma correction) */
    float raw_residual[57];
    for (l = 1; l <= L; l++) {
        int idx = intkl[l];
        int idx1 = idx + 1;
        if (idx1 > 56) idx1 = 56;
        float c1 = 0.65f * (1.0f - deltal[l]) * prev_log2Ml_ext[idx];
        float c2 = 0.65f * deltal[l] * prev_log2Ml_ext[idx1];
        raw_residual[l] = log2Ml_local[l] - c1 - c2 + Sum43;
    }

    /* BigGamma = mean(raw_residual) and Tl = raw_residual - mean */
    /* Actually: raw_residual[l] = Tl[l] + BigGamma
     * So BigGamma = mean(raw_residual) - mean(Tl) + mean(Tl)
     * Wait, let's be precise:
     *   log2Ml = Tl + c1 + c2 - Sum43 + BigGamma
     *   raw_residual = log2Ml - c1 - c2 + Sum43 = Tl + BigGamma
     *   BigGamma = gamma - 0.5*log2(L) - Sum42  where Sum42 = mean(Tl)
     *   So raw_residual[l] = Tl[l] + gamma - 0.5*log2(L) - Sum42
     *   mean(raw_residual) = mean(Tl) + gamma - 0.5*log2(L) - Sum42
     *                      = Sum42 + gamma - 0.5*log2(L) - Sum42
     *                      = gamma - 0.5*log2(L)
     * Therefore: gamma = mean(raw_residual) + 0.5*log2(L)
     */
    float mean_raw = 0.0f;
    for (l = 1; l <= L; l++) {
        mean_raw += raw_residual[l];
    }
    mean_raw /= (float)L;

    float gamma_cur = mean_raw + 0.5f * (logf((float)L) / logf(2.0f));
    *cur_gamma = gamma_cur;

    /* deltaGamma = gamma - 0.5*prev_gamma */
    float deltaGamma = gamma_cur - 0.5f * prev_gamma;

    /* Quantize deltaGamma -> b2 */
    {
        float best_dist_val = FLT_MAX;
        *b2 = 0;
        for (i = 0; i < 32; i++) {
            float d = fabsf(AmbeDg[i] - deltaGamma);
            if (d < best_dist_val) {
                best_dist_val = d;
                *b2 = i;
            }
        }
        /* Use quantized deltaGamma for consistency */
        deltaGamma = AmbeDg[*b2];
        gamma_cur = deltaGamma + 0.5f * prev_gamma;
        *cur_gamma = gamma_cur;
    }

    /* Recompute BigGamma and Tl with quantized gamma */
    Sum42 = 0.0f;
    BigGamma = gamma_cur - 0.5f * (logf((float)L) / logf(2.0f));

    /* Tl = raw_residual - BigGamma
     * But we need to adjust: raw_residual = Tl + BigGamma
     * So Tl = raw_residual - BigGamma */
    for (l = 1; l <= L; l++) {
        Tl[l] = raw_residual[l] - BigGamma;
    }

    /* Verify: Sum42 = mean(Tl) */
    Sum42 = 0.0f;
    for (l = 1; l <= L; l++) {
        Sum42 += Tl[l];
    }
    Sum42 /= (float)L;
    /* Adjust BigGamma to account for quantized gamma */
    BigGamma = gamma_cur - 0.5f * (logf((float)L) / logf(2.0f)) - Sum42;
    /* Re-derive Tl */
    for (l = 1; l <= L; l++) {
        Tl[l] = raw_residual[l] - BigGamma;
    }

    /*
     * Step 4: Forward DCT on each block to get Cik coefficients.
     * The L harmonics are divided into 4 blocks using AmbeLmprbl[L].
     */
    int Ji[5];
    Ji[1] = AmbeLmprbl[L][0];
    Ji[2] = AmbeLmprbl[L][1];
    Ji[3] = AmbeLmprbl[L][2];
    Ji[4] = AmbeLmprbl[L][3];

    /* Split Tl into blocks and do forward DCT for each */
    float Cik[5][18];
    memset(Cik, 0, sizeof(Cik));

    float Tl_block[5][18];
    memset(Tl_block, 0, sizeof(Tl_block));

    int idx_l = 1;
    for (i = 1; i <= 4; i++) {
        for (int j = 1; j <= Ji[i]; j++) {
            if (idx_l <= L) {
                Tl_block[i][j] = Tl[idx_l];
            }
            idx_l++;
        }
        forward_dct(Tl_block[i], Ji[i], Cik[i]);
    }

    /*
     * Step 5: Reconstruct PRBA vector Ri[1..8] from Cik[i][1..2]
     * The decoder does:
     *   Cik[1][1] = 0.5*(Ri[1]+Ri[2])
     *   Cik[1][2] = rconst*(Ri[1]-Ri[2])   rconst = 1/(2*sqrt(2))
     *   Cik[2][1] = 0.5*(Ri[3]+Ri[4])
     *   ...
     * Invert:
     *   Ri[1] = Cik[1][1] + Cik[1][2] / (2*rconst)  ... actually:
     *   Ri[2k-1] = Cik[k][1] + Cik[k][2] * sqrt(2)
     *   Ri[2k]   = Cik[k][1] - Cik[k][2] * sqrt(2)
     */
    float Ri[9];
    float sqrt2 = sqrtf(2.0f);
    Ri[1] = Cik[1][1] + Cik[1][2] * sqrt2;
    Ri[2] = Cik[1][1] - Cik[1][2] * sqrt2;
    Ri[3] = Cik[2][1] + Cik[2][2] * sqrt2;
    Ri[4] = Cik[2][1] - Cik[2][2] * sqrt2;
    Ri[5] = Cik[3][1] + Cik[3][2] * sqrt2;
    Ri[6] = Cik[3][1] - Cik[3][2] * sqrt2;
    Ri[7] = Cik[4][1] + Cik[4][2] * sqrt2;
    Ri[8] = Cik[4][1] - Cik[4][2] * sqrt2;

    /*
     * Step 6: Inverse DCT from Ri to Gm (PRBA vector), then VQ.
     * Decoder: Ri[i] = sum_{m=1}^{8} am*Gm[m]*cos(pi*(m-1)*(i-0.5)/8)
     * Forward: Gm[m] = (2/8)*sum_{i=1}^{8} Ri[i]*cos(pi*(m-1)*(i-0.5)/8)
     * with Gm[1] *= 0.5
     */
    float Gm[9];
    Gm[1] = 0.0f;  /* Gm[1] is always 0 in the AMBE codec */
    for (m = 2; m <= 8; m++) {
        float sum = 0.0f;
        for (i = 1; i <= 8; i++) {
            sum += Ri[i] * cosf((float)M_PI * (float)(m - 1) *
                                ((float)i - 0.5f) / 8.0f);
        }
        Gm[m] = (2.0f / 8.0f) * sum;
    }

    /*
     * Step 7: VQ search for b3 (PRBA24), b4 (PRBA58)
     */
    /* b3: Gm[2..4] -> AmbePRBA24[512][3] */
    {
        float target[3] = { Gm[2], Gm[3], Gm[4] };
        float best = FLT_MAX;
        *b3 = 0;
        for (i = 0; i < 512; i++) {
            float d = vq_dist(target, AmbePRBA24[i], 3);
            if (d < best) {
                best = d;
                *b3 = i;
            }
        }
    }

    /* b4: Gm[5..8] -> AmbePRBA58[128][4] */
    {
        float target[4] = { Gm[5], Gm[6], Gm[7], Gm[8] };
        float best = FLT_MAX;
        *b4 = 0;
        for (i = 0; i < 128; i++) {
            float d = vq_dist(target, AmbePRBA58[i], 4);
            if (d < best) {
                best = d;
                *b4 = i;
            }
        }
    }

    /*
     * Step 8: VQ search for higher-order coefficients b5..b8
     * Cik[block][3..Ji] -> HOC codebooks
     * Each codebook entry has 4 floats (for k=3..6).
     * If Ji < 3, there are no HOC coefficients for that block.
     */

    /* b5: Cik[1][3..6] -> AmbeHOCb5[32][4] */
    {
        float target[4] = {0, 0, 0, 0};
        for (int k = 3; k <= Ji[1] && k <= 6; k++) {
            target[k - 3] = Cik[1][k];
        }
        float best = FLT_MAX;
        *b5 = 0;
        for (i = 0; i < 32; i++) {
            float d = vq_dist(target, AmbeHOCb5[i], 4);
            if (d < best) {
                best = d;
                *b5 = i;
            }
        }
    }

    /* b6: Cik[2][3..6] -> AmbeHOCb6[16][4] */
    {
        float target[4] = {0, 0, 0, 0};
        for (int k = 3; k <= Ji[2] && k <= 6; k++) {
            target[k - 3] = Cik[2][k];
        }
        float best = FLT_MAX;
        *b6 = 0;
        for (i = 0; i < 16; i++) {
            float d = vq_dist(target, AmbeHOCb6[i], 4);
            if (d < best) {
                best = d;
                *b6 = i;
            }
        }
    }

    /* b7: Cik[3][3..6] -> AmbeHOCb7[16][4] */
    {
        float target[4] = {0, 0, 0, 0};
        for (int k = 3; k <= Ji[3] && k <= 6; k++) {
            target[k - 3] = Cik[3][k];
        }
        float best = FLT_MAX;
        *b7 = 0;
        for (i = 0; i < 16; i++) {
            float d = vq_dist(target, AmbeHOCb7[i], 4);
            if (d < best) {
                best = d;
                *b7 = i;
            }
        }
    }

    /* b8: Cik[4][3..6] -> AmbeHOCb8[8][4] */
    {
        float target[4] = {0, 0, 0, 0};
        for (int k = 3; k <= Ji[4] && k <= 6; k++) {
            target[k - 3] = Cik[4][k];
        }
        float best = FLT_MAX;
        *b8 = 0;
        for (i = 0; i < 8; i++) {
            float d = vq_dist(target, AmbeHOCb8[i], 4);
            if (d < best) {
                best = d;
                *b8 = i;
            }
        }
    }
}
