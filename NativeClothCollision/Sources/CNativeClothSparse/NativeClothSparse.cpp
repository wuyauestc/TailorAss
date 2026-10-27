#include "NativeClothSparse.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cfenv>
#include <limits>
#include <new>
#include <vector>

// SDK parameter-error callbacks are synchronous on the invoking thread. Supplying
// one avoids the SDK's default trap; no parameter error can publish a factor.
static thread_local bool ncs_sdk_error=false;
static void ncs_report_error(const char *) { ncs_sdk_error=true; }
static bool cancelled(NCSCancel callback,void *context) { return callback && callback(context)!=0; }
struct NCSSparseWorkspace {
    int dimension=0;
    NCSLimits limits{};
    std::vector<long> columns;
    std::vector<int> rows;
    std::vector<double> values;
    SparseOpaqueSymbolicFactorization symbolic{};
    SparseOpaqueFactorization_Double numeric{};
    bool symbolic_created=false,numeric_created=false,ready=false;
    void *factor_storage=nullptr,*numeric_workspace=nullptr,*solve_workspace=nullptr;
    uint64_t factor_bytes=0,numeric_bytes=0,solve_bytes=0,generation=0,numeric_count=0,solve_count=0;
    ~NCSSparseWorkspace() {
        if(numeric_created)SparseCleanup(numeric);
        if(symbolic_created)SparseCleanup(symbolic);
        std::free(factor_storage);std::free(numeric_workspace);std::free(solve_workspace);
    }
    SparseMatrixStructure structure() {
        SparseAttributes_t attributes{};attributes.kind=SparseSymmetric;attributes.triangle=SparseLowerTriangle;
        return {dimension,dimension,columns.data(),rows.data(),attributes,1};
    }
};
static NCSStatus report(NCSSparseWorkspace *p,NCSReport *out,NCSStatus status,double residual=0,double quadratic=0) {
    if(out){*out={};out->status=status;
        if(p){out->dimension=p->dimension;out->numeric_ready=p->ready;out->numeric_generation=p->generation;
            out->numeric_factorizations=p->numeric_count;out->solve_count=p->solve_count;
            out->factor_bytes_minimum=p->factor_bytes;out->numeric_workspace_bytes=p->numeric_bytes;
            out->solve_workspace_bytes=p->solve_bytes;
            out->matrix_capacity_bytes=p->columns.capacity()*sizeof(long)+p->rows.capacity()*sizeof(int)+p->values.capacity()*sizeof(double);}
        out->relative_residual=residual;out->quadratic_form=quadratic;
    }return status;
}
static double norm(const std::vector<double>&a){double result=0;for(double x:a)result=std::hypot(result,x);return result;}
extern "C" NCSSparseWorkspace *ncs_create(int32_t n,int64_t nnz,const int64_t *columns,const int32_t *rows,
    NCSLimits limits,NCSCancel callback,void *context,NCSReport *out) {
    report(nullptr,out,NCS_INVALID);
    if(!out||!columns||!rows||n<=0||nnz<n||limits.maximum_dofs<=0||limits.maximum_lower_nonzeros<=0||
       limits.maximum_factor_bytes==0||limits.maximum_workspace_bytes==0)return nullptr;
    if(n>limits.maximum_dofs||nnz>limits.maximum_lower_nonzeros){report(nullptr,out,NCS_BUDGET);return nullptr;}
    if(std::fegetround()!=FE_TONEAREST){report(nullptr,out,NCS_UNSUPPORTED_ROUNDING);return nullptr;}
    if(cancelled(callback,context)){report(nullptr,out,NCS_CANCELLED);return nullptr;}
    if(columns[0]!=0||columns[n]!=nnz)return nullptr;
    for(int c=0;c<n;++c){
        if(columns[c]<0||columns[c]>columns[c+1]||columns[c+1]>nnz)return nullptr;
        int previous=-1;bool diagonal=false;
        for(int64_t t=columns[c];t<columns[c+1];++t){
            const int row=rows[t];if(row<c||row>=n||row<=previous)return nullptr;
            previous=row;diagonal|=row==c;
        }
        if(!diagonal)return nullptr;
        if((c&127)==0&&cancelled(callback,context)){report(nullptr,out,NCS_CANCELLED);return nullptr;}
    }
    NCSSparseWorkspace *p=nullptr;
    try {
        p=new NCSSparseWorkspace;p->dimension=n;p->limits=limits;
        p->columns.assign(columns,columns+n+1);p->rows.assign(rows,rows+nnz);p->values.resize(static_cast<size_t>(nnz));
        SparseSymbolicFactorOptions options{};options.control=SparseDefaultControl;options.orderMethod=SparseOrderDefault;
        options.malloc=std::malloc;options.free=std::free;options.reportError=ncs_report_error;
        ncs_sdk_error=false;p->symbolic=SparseFactor(SparseFactorizationCholesky,p->structure(),options);p->symbolic_created=true;
        if(ncs_sdk_error||p->symbolic.status!=SparseStatusOK){report(p,out,NCS_SYMBOLIC_FAILED);delete p;return nullptr;}
        p->factor_bytes=p->symbolic.factorSize_Double;p->numeric_bytes=p->symbolic.workspaceSize_Double;
        if(p->factor_bytes>limits.maximum_factor_bytes||p->numeric_bytes>limits.maximum_workspace_bytes){report(p,out,NCS_BUDGET);delete p;return nullptr;}
        if(cancelled(callback,context)){report(p,out,NCS_CANCELLED);delete p;return nullptr;}
        p->factor_storage=std::malloc(std::max<uint64_t>(p->factor_bytes,16));
        p->numeric_workspace=std::malloc(std::max<uint64_t>(p->numeric_bytes,16));
        if(!p->factor_storage||!p->numeric_workspace){report(p,out,NCS_BUDGET);delete p;return nullptr;}
        report(p,out,NCS_OK);return p;
    } catch(...) {report(p,out,NCS_BUDGET);delete p;return nullptr;}
}
extern "C" NCSStatus ncs_refactor(NCSSparseWorkspace *p,const double *values,int64_t count,
    NCSCancel callback,void *context,NCSReport *out) {
    if(!p)return report(nullptr,out,NCS_INVALID);
    p->ready=false;
    if(!values||count!=static_cast<int64_t>(p->values.size()))return report(p,out,NCS_INVALID);
    if(std::fegetround()!=FE_TONEAREST)return report(p,out,NCS_UNSUPPORTED_ROUNDING);
    if(cancelled(callback,context))return report(p,out,NCS_CANCELLED);
    for(int64_t i=0;i<count;++i){if(!std::isfinite(values[i]))return report(p,out,NCS_INVALID);
        if((i&4095)==0&&cancelled(callback,context))return report(p,out,NCS_CANCELLED);}
    std::copy(values,values+count,p->values.begin());
    SparseMatrix_Double matrix{p->structure(),p->values.data()};ncs_sdk_error=false;
    if(!p->numeric_created){
        SparseNumericFactorOptions options{};options.control=SparseDefaultControl;options.scalingMethod=SparseScalingDefault;
        options.pivotTolerance=0.01;options.zeroTolerance=0;
        p->numeric=SparseFactor(p->symbolic,matrix,options,p->factor_storage,p->numeric_workspace);p->numeric_created=true;
    }else{SparseRefactor(matrix,&p->numeric,p->numeric_workspace);}
    ++p->numeric_count;
    if(ncs_sdk_error||p->numeric.status!=SparseStatusOK)return report(p,out,NCS_NOT_POSITIVE_DEFINITE);
    const size_t a=p->numeric.solveWorkspaceRequiredStatic,b=p->numeric.solveWorkspaceRequiredPerRHS;
    if(a>std::numeric_limits<size_t>::max()-b)return report(p,out,NCS_BUDGET);
    const uint64_t bytes=a+b;
    if(bytes>p->limits.maximum_workspace_bytes)return report(p,out,NCS_BUDGET);
    if(bytes>p->solve_bytes||!p->solve_workspace){
        void *next=std::malloc(std::max<uint64_t>(bytes,16));if(!next)return report(p,out,NCS_BUDGET);
        std::free(p->solve_workspace);p->solve_workspace=next;p->solve_bytes=bytes;
    }
    if(std::fegetround()!=FE_TONEAREST)return report(p,out,NCS_UNSUPPORTED_ROUNDING);
    if(cancelled(callback,context))return report(p,out,NCS_CANCELLED);
    ++p->generation;p->ready=true;return report(p,out,NCS_OK);
}
extern "C" NCSStatus ncs_solve(NCSSparseWorkspace *p,uint64_t generation,const double *rhs,int32_t count,double *solution,
    NCSCancel callback,void *context,NCSReport *out) {
    if(!p)return report(nullptr,out,NCS_INVALID);
    if(!p->ready||generation!=p->generation)return report(p,out,NCS_STALE_FACTOR);
    auto fail=[&](NCSStatus code){p->ready=false;return report(p,out,code);};
    if(!rhs||!solution||count!=p->dimension)return fail(NCS_INVALID);
    if(std::fegetround()!=FE_TONEAREST)return fail(NCS_UNSUPPORTED_ROUNDING);
    if(cancelled(callback,context))return fail(NCS_CANCELLED);
    try {
        std::vector<double> x(count,0),residual(count,0);
        for(int i=0;i<count;++i)if(!std::isfinite(rhs[i]))return fail(NCS_INVALID);
        DenseVector_Double b{count,const_cast<double*>(rhs)},xx{count,x.data()};ncs_sdk_error=false;
        // Public Solve.h parameter names disagree; actual inline implementation is (factor,b,x,workspace).
        SparseSolve(p->numeric,b,xx,p->solve_workspace);
        if(ncs_sdk_error)return fail(NCS_SOLVE_FAILED);
        for(double value:x)if(!std::isfinite(value))return fail(NCS_SOLVE_FAILED);
        for(int c=0;c<count;++c){
            for(long t=p->columns[c];t<p->columns[c+1];++t){const int r=p->rows[t];const double v=p->values[t];
                residual[r]+=v*x[c];if(r!=c)residual[c]+=v*x[r];}
            if((c&127)==0&&cancelled(callback,context))return fail(NCS_CANCELLED);
        }
        double normb=0,quadratic=0;
        for(int i=0;i<count;++i){residual[i]-=rhs[i];normb=std::hypot(normb,rhs[i]);quadratic+=rhs[i]*x[i];}
        const double relative=norm(residual)/(normb>0?normb:1);
        if(!std::isfinite(relative)||!std::isfinite(quadratic)||(normb>0&&quadratic<=0))return fail(NCS_SOLVE_FAILED);
        if(std::fegetround()!=FE_TONEAREST)return fail(NCS_UNSUPPORTED_ROUNDING);
        if(cancelled(callback,context))return fail(NCS_CANCELLED);
        std::copy(x.begin(),x.end(),solution);++p->solve_count;return report(p,out,NCS_OK,relative,quadratic);
    }catch(...){return fail(NCS_BUDGET);}
}
extern "C" void ncs_destroy(NCSSparseWorkspace *p){delete p;}
extern "C" void ncs_invalidate(NCSSparseWorkspace *p,NCSReport *out){
    if(p)p->ready=false;report(p,out,p?NCS_OK:NCS_INVALID);
}
