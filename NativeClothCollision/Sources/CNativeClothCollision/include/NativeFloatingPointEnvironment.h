#ifndef TAILORASS_NATIVE_FLOATING_POINT_ENVIRONMENT_H
#define TAILORASS_NATIVE_FLOATING_POINT_ENVIRONMENT_H
#ifdef __cplusplus
extern "C" {
#endif
/* Read-only fenv bridge: Swift's iOS Darwin importer hides these C symbols. */
int ncc_floating_point_rounding_is_nearest(void);
#ifdef __cplusplus
}
#endif
#endif
