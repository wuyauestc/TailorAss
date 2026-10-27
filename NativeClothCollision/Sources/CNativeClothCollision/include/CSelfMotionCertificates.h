#ifndef C_SELF_MOTION_CERTIFICATES_H
#define C_SELF_MOTION_CERTIFICATES_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Geometry-domain certificates only: these functions do NOT perform CCD.
// A non-certified result never authorizes any movement. Counts refer only to
// the bounded interval certificate, not Tight-Inclusion refinement iterations.
enum NCCSelfCertificateStatus { NCC_SELF_CERT_INVALID=0,NCC_SELF_CERT_CERTIFIED=1,NCC_SELF_CERT_UNCERTAIN=2 };
typedef struct NCCSelfCertificateResult {
 int32_t status,detail;
 int32_t visited_nodes,maximum_depth;
} NCCSelfCertificateResult;
// Exactly9 packed xyz doubles per endpoint (three original triangle vertices).
NCCSelfCertificateResult ncc_self_triangle_certificate(const double*start,size_t start_count,const double*end,size_t end_count,double maximum_time,int32_t maximum_nodes);
// Exactly6 packed xyz doubles per endpoint. Positive initial-edge projection
// is certified for the entire interval; regular large rotations may be refused.
NCCSelfCertificateResult ncc_self_edge_certificate(const double*start,size_t start_count,const double*end,size_t end_count,double maximum_time);
#ifdef __cplusplus
}
#endif
#endif
