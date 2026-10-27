#ifndef TAILORASS_NATIVE_CLOTH_SPARSE_H
#define TAILORASS_NATIVE_CLOTH_SPARSE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// A serial, per-worker Apple Sparse Cholesky workspace, not a cloth solver.
// All arrays are ordinary packed doubles/indices. No geometry/mass is modified.
typedef struct NCSSparseWorkspace NCSSparseWorkspace;
typedef enum {
    NCS_OK=0, NCS_INVALID=1, NCS_CANCELLED=2, NCS_BUDGET=3,
    NCS_UNSUPPORTED_ROUNDING=4, NCS_SYMBOLIC_FAILED=5,
    NCS_NOT_POSITIVE_DEFINITE=6, NCS_SOLVE_FAILED=7, NCS_STALE_FACTOR=8
} NCSStatus;
typedef int (*NCSCancel)(void *context);
typedef struct {
    int64_t maximum_dofs,maximum_lower_nonzeros;
    uint64_t maximum_factor_bytes,maximum_workspace_bytes;
} NCSLimits;
typedef struct {
    int status,dimension,numeric_ready;
    uint64_t numeric_generation,numeric_factorizations,solve_count;
    uint64_t factor_bytes_minimum,numeric_workspace_bytes,solve_workspace_bytes,matrix_capacity_bytes;
    double relative_residual,quadratic_form;
} NCSReport;
// Lower symmetric CSC, sorted unique rows >=column, every diagonal present.
// Symbolic ordering only, performed once. Counts/budgets checked before numeric allocation.
NCSSparseWorkspace *ncs_create(int32_t dimension,int64_t lower_nonzeros,
    const int64_t *column_starts,const int32_t *row_indices,NCSLimits limits,
    NCSCancel is_cancelled,void *cancel_context,NCSReport *report);
// A failed/cancelled update invalidates numeric readiness; no stale factor reuse.
// No jitter, compliance, scaling of the physical input or matrix repair is added.
NCSStatus ncs_refactor(NCSSparseWorkspace *workspace,const double *values,int64_t value_count,
    NCSCancel is_cancelled,void *cancel_context,NCSReport *report);
// Stages output privately. Failure/cancellation leaves caller solution untouched.
// expected_generation must be that returned by the last successful refactor.
NCSStatus ncs_solve(NCSSparseWorkspace *workspace,uint64_t expected_generation,
    const double *rhs,int32_t count,double *solution,
    NCSCancel is_cancelled,void *cancel_context,NCSReport *report);
// Invalidates cached numeric readiness without altering the immutable pattern.
void ncs_invalidate(NCSSparseWorkspace *workspace,NCSReport *report);
void ncs_destroy(NCSSparseWorkspace *workspace);
#ifdef __cplusplus
}
#endif
#endif
