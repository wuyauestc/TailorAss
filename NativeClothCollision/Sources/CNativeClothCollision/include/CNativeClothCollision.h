#ifndef C_NATIVE_CLOTH_COLLISION_H
#define C_NATIVE_CLOTH_COLLISION_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef enum NCCStatus {
    NCC_STATUS_INVALID = 0,
    NCC_STATUS_NO_HIT = 1,
    NCC_STATUS_CONSERVATIVE_HIT = 2,
    NCC_STATUS_UNCERTAIN = 3
} NCCStatus;
typedef enum NCCDetail {
    NCC_DETAIL_NONE = 0,
    NCC_DETAIL_INVALID_ARGUMENT = 1,
    NCC_DETAIL_UNSUPPORTED_SCALE = 2,
    NCC_DETAIL_UNCERTAIN_GEOMETRY = 3,
    NCC_DETAIL_PRECISION_OR_BUDGET = 4,
    NCC_DETAIL_ROUNDING_MODE = 5,
    NCC_DETAIL_INTERNAL_FAILURE = 6
} NCCDetail;
typedef struct NCCOptions {
    double minimum_separation; // meters, >=0 and below upstream per-axis coordinate scale
    double maximum_time;       // fraction of the supplied whole motion, (0,1]
    double distance_tolerance; // meters, (0,1]
    int64_t maximum_iterations; // [1,100000], finite upstream root-search refinement budget
} NCCOptions;
typedef struct NCCResult {
    int32_t status;
    int32_t detail;
    double conservative_time_of_impact; // infinity ONLY for NO_HIT; 0 for unsupported/failed query
    double achieved_distance_tolerance; // infinity if unknown; may exceed requested precision
    int64_t configured_iteration_budget; // NOT an observed iteration count
} NCCResult;

// start/end must each contain exactly 12 doubles (4 xyz points).
// VF order: vertex, triangle0, triangle1, triangle2. EE: edgeA0,A1,edgeB0,B1.
// Moving points interpolate linearly over [0,1]; only [0,maximum_time] is queried.
// Hit is conservative and can be a false positive. UNCERTAIN is never safe to advance.
// An initially touching configuration returns a hit at 0; no_zero_toi is always false.
// Values outside abs(coordinate)<=1e6 meters are explicitly unsupported.
// Degenerate/poorly conditioned primitives, or no certified nondegeneracy along the
// queried motion, return UNCERTAIN. This intentionally includes some regular large rotations.
// Only round-to-nearest IEEE754 double is supported. No input arrays are modified.
// Thread safe between independent calls; cancellation may be checked between bounded calls.
NCCResult ncc_vertex_face(
    const double *start, size_t start_count,
    const double *end, size_t end_count, NCCOptions options);
NCCResult ncc_edge_edge(
    const double *start, size_t start_count,
    const double *end, size_t end_count, NCCOptions options);
const char *ncc_upstream_revision(void);
#ifdef __cplusplus
}
#endif
#endif

