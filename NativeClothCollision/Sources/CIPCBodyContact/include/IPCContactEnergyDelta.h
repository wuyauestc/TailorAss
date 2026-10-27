#ifndef TAILORASS_IPC_CONTACT_ENERGY_DELTA_H
#define TAILORASS_IPC_CONTACT_ENERGY_DELTA_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Independent incremental evaluation of the same fixed signed IPC leaf.
 * This is a binary64 estimate, not an interval/sign certificate. It changes
 * neither the original energy, gradient, Hessian, nor any contact threshold. */
typedef int (*IPCEDCancel)(void *);
enum IPCEDStatus {
    IPCED_OK=0, IPCED_INVALID=1, IPCED_INFEASIBLE=2, IPCED_DEGENERATE=3,
    IPCED_NUMERICAL=4, IPCED_CANCELLED=5, IPCED_DISTANCE_TYPE_CHANGED=6,
    IPCED_UNSUPPORTED_ROUNDING=7
};
typedef struct {
    int status;
    int previous_distance_type;
    int current_distance_type;
    uint32_t activation_transition;
    uint32_t mollifier_transition;
    double delta_joules;
} IPCEDResult;
int ipced_evaluate_local(int kind,const double *previous_xyz,size_t previous_count,
    const double *current_xyz,size_t current_count,const double *rest_xyz,size_t rest_count,
    int cached_distance_type,double signed_area_m2,double kappa_pa,
    double minimum_distance_m,double activation_gap_m,
    IPCEDCancel cancelled,void *cancel_context,IPCEDResult *output);
#ifdef __cplusplus
}
#endif
#endif
