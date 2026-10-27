#ifndef TAILORASS_IPC_CLOTH_CONTACT_BUILDER_H
#define TAILORASS_IPC_CLOTH_CONTACT_BUILDER_H
#include "IPCEnergy.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// All triangle-surface source DOFs move. Adjacency is REAL primitive vertex-ID
// incidence only, never a triangle-pair/sewing/panel exclusion. Caller supplies
// a complete conservative unordered face-pair set, including shared-ID faces.
typedef struct IPCCPrepared IPCCPrepared;
typedef struct {uint32_t face0,face1;} IPCCFacePair;
typedef int (*IPCCCancel)(void*context);
typedef struct {
 int kind,num_vertices,distance_type;
 uint32_t vertex_ids[4];
 double signed_rest_area_m2;
 IPCEnergyResult local;
} IPCCBlock;
typedef void (*IPCCBlockConsumer)(const IPCCBlock*block,void*context);
typedef struct {
 int status;
 size_t candidate_count,stencil_count,negative_stencil_count;
 size_t fv_count,ev_count,ee_count,vv_count;
 double energy_joules,minimum_candidate_distance_meters;
} IPCCResult;
IPCCPrepared*ipcc_create(const double*rest_xyz,size_t vertex_count,const uint32_t*triangles,size_t triangle_count,
 size_t maximum_candidates,size_t maximum_stencils,IPCCCancel is_cancelled,void*cancel_context,int*out_status);
void ipcc_destroy(IPCCPrepared*prepared);
// Whole signed local RAW/PSD block is emitted with ALL original moving IDs.
// Nonzero status invalidates every E/G/block from the trial; stage privately.
int ipcc_evaluate(const IPCCPrepared*prepared,const double*current_xyz,size_t current_count,
 const IPCCFacePair*pairs,size_t pair_count,double kappa_pa,double dmin_m,double h_m,int hessian_mode,
 double*out_gradient,size_t gradient_count,IPCCBlockConsumer consumer,void*consumer_context,
 IPCCCancel is_cancelled,void*cancel_context,IPCCResult*out_result);
#ifdef __cplusplus
}
#endif
#endif
