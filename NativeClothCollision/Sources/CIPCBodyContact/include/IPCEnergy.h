#ifndef TAILORASS_IPC_ENERGY_H
#define TAILORASS_IPC_ENERGY_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Temporary research ABI. All xyz are packed triples, never padded SIMD rows.
// All lengths are metres. Weight is a signed reference area (m²), κ is Pa.
// A nonzero status invalidates all E/G/H values; callers must never accept them.
enum IPCEnergyKind { IPCE_VV=0, IPCE_EV=1, IPCE_EE=2, IPCE_FV=3 };
enum IPCEnergyStatus { IPCE_OK=0, IPCE_INVALID=1, IPCE_INFEASIBLE=2, IPCE_DEGENERATE=3, IPCE_NUMERICAL=4 };
enum IPCEnergyPSD { IPCE_RAW_HESSIAN=0, IPCE_CLAMP_PSD=1, IPCE_ABS_PSD=2 };
typedef struct {
    int status;
    int dof_count;
    int distance_type;
    int hessian_mode;
    double energy_joules;
    double distance_squared_m2;
    double mollifier;
    double mollifier_threshold_m4;
    double gradient_newtons[12];
    double hessian_row_major_newtons_per_meter[144];
} IPCEnergyResult;
int ipce_evaluate_local(int kind,const double*current_xyz,size_t current_count,
    const double*rest_xyz,size_t rest_count,int distance_type,
    double signed_area_m2,double kappa_pa,double minimum_distance_m,
    double activation_gap_m,int hessian_mode,IPCEnergyResult*out);
size_t ipce_result_sizeof(void);
#ifdef __cplusplus
}
#endif
#endif
