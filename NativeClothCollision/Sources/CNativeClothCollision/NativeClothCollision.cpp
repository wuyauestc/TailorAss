#include "include/CNativeClothCollision.h"
#include "TriangleNormCertificate.hpp"
#include <tight_inclusion/ccd.hpp>
#include <algorithm>
#include <cfenv>
#include <cmath>
#include <limits>

static_assert(std::numeric_limits<double>::is_iec559 && sizeof(double)==8, "IEEE754 Double required");
static_assert(sizeof(long)>=8, "64-bit platform required");
namespace {
using V = ticcd::Vector3;
constexpr double inf = std::numeric_limits<double>::infinity();
NCCResult result(int status,int detail,const NCCOptions &o,double toi=0,double tol=inf) {
    return {status,detail,toi,tol,o.maximum_iterations};
}
V at(const double *x,int i) {return V(x[3*i],x[3*i+1],x[3*i+2]);}
V cross(const V &a,const V &b) {
    return V(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]);
}
// Validation certificate only. Original Tight-Inclusion predicates/CCD are unchanged.
bool triangleCertified(const double *a,const double *b,double t) {
    const V u=at(a,2)-at(a,1),v=at(a,3)-at(a,1);
    const V du=(at(b,2)-at(b,1))-u,dv=(at(b,3)-at(b,1))-v;
    const V n=cross(u,v);
    const double area=n.norm(),scale=std::max(u.squaredNorm(),v.squaredNorm());
    const double eps=std::max(1e-24,scale*1e-12);
    if(!std::isfinite(area)||area<=eps)return false;
    const V normal=n/area;
    const double c1=(cross(du,v)+cross(u,dv)).dot(normal),c2=cross(du,dv).dot(normal);
    // Quadratic Bernstein lower bound on signed area projected onto the initial normal.
    return area>eps && area+.5*t*c1>eps && area+t*c1+t*t*c2>eps;
}
// Preserve the original successful fixed-normal certificate above unchanged.
// Its conservative failure may be a rotating, nonzero triangle. Only then use
// our interval norm certificate with exactly the same original numerical eps.
bool triangleNormCertified(const double *a,const double *b,double t) {
    const V u=at(a,2)-at(a,1),v=at(a,3)-at(a,1),n=cross(u,v);
    const double area=n.norm(),scale=std::max(u.squaredNorm(),v.squaredNorm());
    const double eps=std::max(1e-24,scale*1e-12);
    if(!std::isfinite(area)||area<=eps)return false;
    return ncc_triangle_norm::certified(a,b,t,eps);
}
bool edgeCertified(const double *a,const double *b,int i,int j,double t) {
    const V e=at(a,j)-at(a,i),eEnd=e+t*((at(b,j)-at(b,i))-e);
    const double len=e.norm(),endLen=eEnd.norm();
    if(!std::isfinite(len)||!std::isfinite(endLen)||len<=1e-12||endLen<=1e-12)return false;
    // A positive linear projection throughout [0,t] certifies the edge cannot collapse.
    return e.dot(eEnd)>std::max(1e-24,len*endLen*1e-12);
}
template<bool VF>
NCCResult query(const double *a,size_t ac,const double *b,size_t bc,NCCOptions o) {
    if(!a||!b||ac!=12||bc!=12||!std::isfinite(o.minimum_separation)||
       !std::isfinite(o.maximum_time)||!std::isfinite(o.distance_tolerance)||
       o.minimum_separation<0||o.maximum_time<=0||o.maximum_time>1||
       o.distance_tolerance<=0||o.distance_tolerance>1||
       o.maximum_iterations<1||o.maximum_iterations>100000)
        return result(NCC_STATUS_INVALID,NCC_DETAIL_INVALID_ARGUMENT,o);
    double scales[3]={1,1,1};
    for(int i=0;i<12;i++){
        if(!std::isfinite(a[i])||!std::isfinite(b[i]))
            return result(NCC_STATUS_INVALID,NCC_DETAIL_INVALID_ARGUMENT,o);
        if(std::abs(a[i])>1e6||std::abs(b[i])>1e6)
            return result(NCC_STATUS_INVALID,NCC_DETAIL_UNSUPPORTED_SCALE,o);
        scales[i%3]=std::max({scales[i%3],std::abs(a[i]),std::abs(b[i])});
    }
    // Explicitly uphold the minimum-separation domain documented by upstream.
    if(o.minimum_separation>=std::min({scales[0],scales[1],scales[2]}))
        return result(NCC_STATUS_INVALID,NCC_DETAIL_UNSUPPORTED_SCALE,o);
    if(std::fegetround()!=FE_TONEAREST)
        return result(NCC_STATUS_UNCERTAIN,NCC_DETAIL_ROUNDING_MODE,o);
    if constexpr(VF) {
        if(!triangleCertified(a,b,o.maximum_time)&&!triangleNormCertified(a,b,o.maximum_time))
            return result(NCC_STATUS_UNCERTAIN,NCC_DETAIL_UNCERTAIN_GEOMETRY,o);
    } else {
        if(!edgeCertified(a,b,0,1,o.maximum_time)||!edgeCertified(a,b,2,3,o.maximum_time))
            return result(NCC_STATUS_UNCERTAIN,NCC_DETAIL_UNCERTAIN_GEOMETRY,o);
    }
    try {
        double toi=inf,tol=inf;bool hit;
        const ticcd::Array3 err(-1,-1,-1); // per-query floating point error bound
        if constexpr(VF) {
            hit=ticcd::vertexFaceCCD(at(a,0),at(a,1),at(a,2),at(a,3),
                at(b,0),at(b,1),at(b,2),at(b,3),err,o.minimum_separation,toi,
                o.distance_tolerance,o.maximum_time,static_cast<long>(o.maximum_iterations),tol,false);
        } else {
            hit=ticcd::edgeEdgeCCD(at(a,0),at(a,1),at(a,2),at(a,3),
                at(b,0),at(b,1),at(b,2),at(b,3),err,o.minimum_separation,toi,
                o.distance_tolerance,o.maximum_time,static_cast<long>(o.maximum_iterations),tol,false);
        }
        if(!std::isfinite(tol)||tol>o.distance_tolerance*(1+8*std::numeric_limits<double>::epsilon()))
            return result(NCC_STATUS_UNCERTAIN,NCC_DETAIL_PRECISION_OR_BUDGET,o,
                          std::isfinite(toi)&&toi>=0?std::min(toi,o.maximum_time):0,tol);
        if(!hit)return result(NCC_STATUS_NO_HIT,NCC_DETAIL_NONE,o,inf,tol);
        if(!std::isfinite(toi)||toi<0||toi>o.maximum_time)
            return result(NCC_STATUS_UNCERTAIN,NCC_DETAIL_INTERNAL_FAILURE,o);
        return result(NCC_STATUS_CONSERVATIVE_HIT,NCC_DETAIL_NONE,o,toi,tol);
    } catch(...) {
        return result(NCC_STATUS_UNCERTAIN,NCC_DETAIL_INTERNAL_FAILURE,o);
    }
}
}
extern "C" NCCResult ncc_vertex_face(const double *a,size_t ac,const double *b,size_t bc,NCCOptions o){
    return query<true>(a,ac,b,bc,o);
}
extern "C" NCCResult ncc_edge_edge(const double *a,size_t ac,const double *b,size_t bc,NCCOptions o){
    return query<false>(a,ac,b,bc,o);
}
extern "C" const char *ncc_upstream_revision(void){
    return "Tight-Inclusion 1.0.4 6f84001a790a9d3362b7c13d410037140d83fa2c";
}

