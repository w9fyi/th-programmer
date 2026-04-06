/*
 * Extern declarations for mbelib codebook tables.
 * The actual definitions live in mbelib's ambe3600x2450_const.h and ecc_const.h.
 * We declare them extern here to avoid duplicate symbol errors.
 */

#ifndef AMBE_TABLES_EXTERN_H
#define AMBE_TABLES_EXTERN_H

/* From ambe3600x2450_const.h */
extern const float AmbeW0table[120];
extern const float AmbeLtable[120];
extern const int   AmbeVuv[32][8];
extern const int   AmbeLmprbl[57][4];
extern const float AmbeDg[32];
extern const float AmbePRBA24[512][3];
extern const float AmbePRBA58[128][4];
extern const float AmbeHOCb5[32][4];
extern const float AmbeHOCb6[16][4];
extern const float AmbeHOCb7[16][4];
extern const float AmbeHOCb8[8][4];

/* From ecc_const.h */
extern const int golayGenerator[12];
extern const int golayMatrix[2048];
extern const int hammingGenerator[4];
extern const int hammingMatrix[16];

#endif /* AMBE_TABLES_EXTERN_H */
