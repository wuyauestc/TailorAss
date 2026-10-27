#ifndef TAILORASS_IPC_CONTACT_BUILDER_H
#define TAILORASS_IPC_CONTACT_BUILDER_H
#include "IPCEnergy.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Temporary surface-only serial prototype. Body vertices are fixed DOFs, not zero-area features.
// External broad phase MUST supply all cloth/body face pairs whose AABBs overlap
// after total expansion dmin+h (e.g. existing Prepared.candidateTriangleIDs BVH).
// Only an exterior bootstrap + complete CBC can certify exterior/no crossing.
// Unsigned barrier energy alone makes neither claim.
enum IPCBStatus { IPCB_CANCELLED=5, IPCB_BUDGET=6, IPCB_UNSUPPORTED_TOPOLOGY=7 };
typedef struct IPCBPrepared IPCBPrepared;
typedef struct { uint32_t cloth_face,body_face; } IPCBFacePair;
typedef int (*IPCBCancel)(void*context);
typedef struct {
 int kind,num_vertices,distance_type;
 uint32_t vertex_ids[4];
 double signed_rest_area_m2;
 IPCEnergyResult local;
} IPCBBlock;
// IDs remain original independent source DOFs. local Hessian is full-stencil
// RAW or whole-local-PSD BEFORE restricting rows/columns to cloth vertex IDs.
typedef void (*IPCBBlockConsumer)(const IPCBBlock*block,void*context);
typedef struct {
 int status;
 size_t candidate_count,stencil_count,negative_stencil_count;
 size_t fv_count,bvf_count,ev_count,ee_count,vv_count;
 double energy_joules,minimum_candidate_distance_meters;
} IPCBResult;
IPCBPrepared*ipcb_create(const double*rest_xyz,size_t vertex_count,size_t cloth_vertex_count,
 const uint32_t*triangles,size_t triangle_count,size_t maximum_candidates,size_t maximum_stencils,
 IPCBCancel is_cancelled,void*cancel_context,int*out_status);
void ipcb_destroy(IPCBPrepared*prepared);
// current_count is the number of packed doubles (3*vertex_count). Body current
// coordinates must equal prepared fixed-body rest coordinates exactly.
// gradient_count=3*cloth_vertex_count. Any nonzero status invalidates ALL trial
// outputs, including staged consumer blocks. Caller must discard the whole trial.
int ipcb_evaluate(const IPCBPrepared*prepared,const double*current_xyz,size_t current_count,
 const IPCBFacePair*pairs,size_t pair_count,double kappa_pa,double dmin_m,double h_m,int hessian_mode,
 double*out_cloth_gradient,size_t gradient_count,IPCBBlockConsumer consumer,void*consumer_context,
 IPCBCancel is_cancelled,void*cancel_context,IPCBResult*out_result);
#ifdef __cplusplus
}
#endif
#endif
