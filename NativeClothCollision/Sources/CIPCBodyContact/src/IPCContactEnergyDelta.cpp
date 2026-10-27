// Original increment derivation by this project. The real-valued physical
// function is IPC v1.6.1's fixed distance leaf, signed area, mollifier and
// clamped logarithmic barrier. No upstream energy/derivative file is modified.
#include "IPCContactEnergyDelta.h"
#include <ipc/distance/distance_type.hpp>
#include <Eigen/Geometry>
#include <algorithm>
#include <array>
#include <cfenv>
#include <cmath>
#include <limits>
namespace {
using V=Eigen::Vector3d;
struct Bad {int status;};
double sum(double a,double b){double s=a+b;return s+(std::abs(a)>=std::abs(b)?(a-s)+b:(b-s)+a);}
double dot(const V&a,const V&b){return sum(sum(a.x()*b.x(),a.y()*b.y()),a.z()*b.z());}
double n2(const V&a){return dot(a,a);}
double dn2(const V&a,const V&da){return sum(2*dot(a,da),n2(da));}
V dcross(const V&u,const V&v,const V&du,const V&dv){return u.cross(dv)+du.cross(v)+du.cross(dv);}
struct Increment {double value,delta;};
Increment quotient(double n,double d,double dn,double dd){
    if(!(d>0)||!(d+dd>0))throw Bad{IPCED_DEGENERATE};
    double value=n/d;return {value,(dn-value*dd)/(d+dd)};
}
Increment pp(const V&a,const V&b,const V&da,const V&db){V r=a-b,dr=da-db;return {n2(r),dn2(r,dr)};}
Increment pe(const V&p,const V&a,const V&b,const V&dp,const V&da,const V&db){
    V r=p-a,u=b-a,dr=dp-da,du=db-da,k=r.cross(u),dk=dcross(r,u,dr,du);
    return quotient(n2(k),n2(u),dn2(k,dk),dn2(u,du));
}
Increment normal(const V&r,const V&u,const V&v,const V&dr,const V&du,const V&dv){
    V n=u.cross(v),dn=dcross(u,v,du,dv);double h=dot(r,n),dh=sum(sum(dot(r,dn),dot(dr,n)),dot(dr,dn));
    // Relative normal degeneracy is explicit; do not manufacture a finite
    // quotient for collapsed or effectively parallel supporting planes.
    if(n2(n)<=std::max(1e-48,n2(u)*n2(v)*1e-24))throw Bad{IPCED_DEGENERATE};
    return quotient(h*h,n2(n),dh*(2*h+dh),dn2(n,dn));
}
int dtype(int kind,const std::array<V,4>&p,int cached){
    if(kind==0)return 0;
    if(cached>=0)return cached;
    if(kind==1)return int(ipc::point_edge_distance_type(p[0],p[1],p[2]));
    if(kind==2)return int(ipc::edge_edge_distance_type(p[0],p[1],p[2],p[3]));
    return int(ipc::point_triangle_distance_type(p[0],p[1],p[2],p[3]));
}
Increment distance(int kind,int t,const std::array<V,4>&p,const std::array<V,4>&dp){
    if(kind==0)return pp(p[0],p[1],dp[0],dp[1]);
    if(kind==1){if(t<2)return pp(p[0],p[t+1],dp[0],dp[t+1]);return pe(p[0],p[1],p[2],dp[0],dp[1],dp[2]);}
    if(kind==2){
        if(t<4)return pp(p[t/2],p[2+t%2],dp[t/2],dp[2+t%2]);
        if(t<6)return pe(p[t-2],p[0],p[1],dp[t-2],dp[0],dp[1]);
        if(t<8)return pe(p[t-6],p[2],p[3],dp[t-6],dp[2],dp[3]);
        return normal(p[0]-p[2],p[1]-p[0],p[3]-p[2],dp[0]-dp[2],dp[1]-dp[0],dp[3]-dp[2]);
    }
    if(t<3)return pp(p[0],p[t+1],dp[0],dp[t+1]);
    if(t<6){constexpr int edges[3][2]={{1,2},{2,3},{3,1}};auto e=edges[t-3];return pe(p[0],p[e[0]],p[e[1]],dp[0],dp[e[0]],dp[e[1]]);}
    return normal(p[0]-p[1],p[2]-p[1],p[3]-p[1],dp[0]-dp[1],dp[2]-dp[1],dp[3]-dp[1]);
}
bool triangleValid(const V&a,const V&b,const V&c){V u=b-a,v=c-a;return u.cross(v).norm()>std::max(1e-24,std::max(u.squaredNorm(),v.squaredNorm())*1e-12);}
void geometry(int kind,const std::array<V,4>&p){
    if((kind==1&&(p[2]-p[1]).norm()<=1e-12)||
       (kind==2&&((p[1]-p[0]).norm()<=1e-12||(p[3]-p[2]).norm()<=1e-12))||
       (kind==3&&!triangleValid(p[1],p[2],p[3])))throw Bad{IPCED_DEGENERATE};
}
double logRatio(double q,double Q){double s=q-Q;return std::abs(s)<Q*.5?std::log1p(s/Q):std::log(q/Q);}
double barrier(double q,double Q){return q>=Q?0:-(q-Q)*(q-Q)*logRatio(q,Q);}
Increment barrierIncrement(double q,double dq,double Q){
    double q1=q+dq;if(!(q>0)||!(q1>0))throw Bad{IPCED_INFEASIBLE};
    double b=barrier(q,Q);
    if(q>=Q)return {b,barrier(q1,Q)};
    if(q1>=Q)return {b,-b};
    double s=q-Q;
    double dl=std::abs(dq)<q*.5?std::log1p(dq/q):std::log(q1/q);
    return {b,-sum(dq*(2*s+dq)*logRatio(q,Q),(s+dq)*(s+dq)*dl)};
}
Increment mollifier(const std::array<V,4>&p,const std::array<V,4>&dp,double eps){
    V u=p[1]-p[0],v=p[3]-p[2],du=dp[1]-dp[0],dv=dp[3]-dp[2];
    V n=u.cross(v),dn=dcross(u,v,du,dv);double c=n2(n),dc=dn2(n,dn),c1=c+dc;
    if(c>=eps){if(c1>=eps)return {1,0};double z=c1/eps;return {1,-(1-z)*(1-z)};}
    double z=c/eps,m=z*(2-z);
    if(c1>=eps)return {m,(1-z)*(1-z)};
    return {m,(dc/eps)*(2-(2*c+dc)/eps)};
}
}
extern "C" int ipced_evaluate_local(int kind,const double*x0,size_t n0,const double*x1,size_t n1,const double*rest,size_t nr,int cached,double w,double k,double dm,double h,IPCEDCancel cancel,void*ctx,IPCEDResult*out){
    if(!out)return IPCED_INVALID;
    *out={};out->status=IPCED_INVALID;out->delta_joules=std::numeric_limits<double>::quiet_NaN();
    auto fail=[&](int s){out->status=s;out->delta_joules=std::numeric_limits<double>::quiet_NaN();return s;};
    if(cancel&&cancel(ctx))return fail(IPCED_CANCELLED);
    if(std::fegetround()!=FE_TONEAREST)return fail(IPCED_UNSUPPORTED_ROUNDING);
    const int nv=kind==0?2:(kind==1?3:4),maxType=kind==0?0:(kind==1?2:(kind==2?8:6));
    if(kind<0||kind>3||!x0||!x1||!rest||n0!=size_t(nv*3)||n1!=n0||nr!=n0||cached< -1||cached>maxType||!std::isfinite(w)||!std::isfinite(k)||k<=0||!std::isfinite(dm)||dm<0||!std::isfinite(h)||h<=0)return fail(IPCED_INVALID);
    try{
        std::array<V,4>a,b,r,dp;
        for(int i=0;i<nv;++i){for(int j=0;j<3;++j)if(!std::isfinite(x0[3*i+j])||!std::isfinite(x1[3*i+j])||!std::isfinite(rest[3*i+j])||std::abs(x0[3*i+j])>1e6||std::abs(x1[3*i+j])>1e6||std::abs(rest[3*i+j])>1e6)throw Bad{IPCED_INVALID};a[i]=V(x0[3*i],x0[3*i+1],x0[3*i+2]);b[i]=V(x1[3*i],x1[3*i+1],x1[3*i+2]);r[i]=V(rest[3*i],rest[3*i+1],rest[3*i+2]);dp[i]=b[i]-a[i];}
        geometry(kind,a);geometry(kind,b);
        int ta=dtype(kind,a,cached),tb=dtype(kind,b,cached);out->previous_distance_type=ta;out->current_distance_type=tb;
        if(ta!=tb)throw Bad{IPCED_DISTANCE_TYPE_CHANGED};
        Increment d=distance(kind,ta,a,dp);double Q=(2*dm+h)*h,scale=k*h/(Q*Q),q=d.value-dm*dm;
        if(!std::isfinite(Q)||Q<=0||!std::isfinite(scale))throw Bad{IPCED_NUMERICAL};
        auto B=barrierIncrement(q,d.delta,Q);Increment m{1,0};out->activation_transition=(q<Q)!=(q+d.delta<Q);
        if(kind==2){double eps=1e-3*(r[0]-r[1]).squaredNorm()*(r[2]-r[3]).squaredNorm();if(!(eps>0)||!std::isfinite(eps))throw Bad{IPCED_DEGENERATE};m=mollifier(a,dp,eps);double c0=n2((a[1]-a[0]).cross(a[3]-a[2])),c1=n2((b[1]-b[0]).cross(b[3]-b[2]));out->mollifier_transition=(c0<eps)!=(c1<eps);}
        double delta=w*scale*sum(m.value*B.delta,(B.value+B.delta)*m.delta);
        if(!std::isfinite(delta))throw Bad{IPCED_NUMERICAL};
        if(cancel&&cancel(ctx))throw Bad{IPCED_CANCELLED};
        if(std::fegetround()!=FE_TONEAREST)throw Bad{IPCED_UNSUPPORTED_ROUNDING};
        out->delta_joules=delta;out->status=IPCED_OK;return out->status;
    }catch(const Bad&e){return fail(e.status);}catch(...){return fail(IPCED_NUMERICAL);}
}
