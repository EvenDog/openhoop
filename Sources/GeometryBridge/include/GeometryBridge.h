#ifndef EMBROIDERY_GEOMETRY_BRIDGE_H
#define EMBROIDERY_GEOMETRY_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double *xy; int32_t *counts; int32_t path_count; int32_t point_count; int32_t error; int32_t *parents; } EGPaths;
// All units are mm; output ownership belongs to the caller until eg_free_paths.
EGPaths eg_offset(const double *xy, const int32_t *counts, int32_t path_count, double delta);
EGPaths eg_resolve(const double *xy, const int32_t *counts, int32_t path_count, int32_t nonzero);
// Subject minus clip, each read with the even-odd rule (so holes stay holes). The result carries each ring's
// parent ring (-1 for outer rings), like eg_resolve.
EGPaths eg_difference(const double *subject_xy, const int32_t *subject_counts, int32_t subject_count,
                      const double *clip_xy, const int32_t *clip_counts, int32_t clip_count);
void eg_free_paths(EGPaths paths);
#ifdef __cplusplus
}
#endif
#endif
