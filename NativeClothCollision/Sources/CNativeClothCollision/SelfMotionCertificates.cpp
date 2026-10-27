#include "CSelfMotionCertificates.h"
#include "CNativeClothCollision.h"
#include "TriangleNormCertificate.hpp"
#include <algorithm>
#include <array>
#include <cfenv>
#include <cmath>
#include <limits>
static_assert(sizeof(double)==8&&std::numeric_limits<double>::is_iec559,"IEEE754 Double required");
namespace {
using I=ncc_triangle_norm::Interval;using V=ncc_triangle_norm::Vector;
NCCSelfCertificateResult result(int status,int detail,int nodes=0,int depth=0){return {status,detail,nodes,depth};}
bool valid(const double*a,size_t ac,const double*b,size_t bc,size_t n,double time){if(!a||!b||ac!=n||bc!=n||!std::isfinite(time)||time<=0||time>1)return false;for(size_t i=0;i<n;++i)if(!std::isfinite(a[i])||!std::isfinite(b[i]))return false;return true;}
bool scale(const double*a,const double*b,size_t n){for(size_t i=0;i<n;++i)if(std::abs(a[i])>1e6||std::abs(b[i])>1e6)return false;return true;}
int ieeeDetail(){return std::fegetround()!=FE_TONEAREST?NCC_DETAIL_ROUNDING_MODE:NCC_DETAIL_UNCERTAIN_GEOMETRY;}
struct Observer {
 int nodes=0,depth=0;ncc_triangle_norm::Reason reason=ncc_triangle_norm::Reason::invalid;
 void start(I,I,const ncc_triangle_norm::Coefficients&){}
 void accepted(std::uint32_t,int,const ncc_triangle_norm::Coefficients&){}
 void finish(ncc_triangle_norm::Reason r,int n,int d){reason=r;nodes=n;depth=d;}
};
}
extern "C" NCCSelfCertificateResult ncc_self_triangle_certificate(const double*a,size_t ac,const double*b,size_t bc,double t,int32_t maximumNodes){
 if(!valid(a,ac,b,bc,9,t)||maximumNodes<1||maximumNodes>ncc_triangle_norm::maximumNodes)return result(NCC_SELF_CERT_INVALID,NCC_DETAIL_INVALID_ARGUMENT);
 if(!scale(a,b,9))return result(NCC_SELF_CERT_INVALID,NCC_DETAIL_UNSUPPORTED_SCALE);
 if(!ncc_triangle_norm::ieeeReady())return result(NCC_SELF_CERT_UNCERTAIN,ieeeDetail());
 // Private triangle-norm kernel uses the original VF12-coordinate convention;
 // the unused first xyz slot is an exact copy, not an added simulation vertex.
 double aa[12]{},bb[12]{};for(int i=0;i<9;++i){aa[i+3]=a[i];bb[i+3]=b[i];}for(int i=0;i<3;++i){aa[i]=a[i];bb[i]=b[i];}
 double u[3],v[3];for(int i=0;i<3;++i){u[i]=a[i+3]-a[i];v[i]=a[i+6]-a[i];}
 const double uu=u[0]*u[0]+u[1]*u[1]+u[2]*u[2],vv=v[0]*v[0]+v[1]*v[1]+v[2]*v[2];
 const double epsilon=std::max(1e-24,std::max(uu,vv)*1e-12);
 Observer observer;const bool ok=ncc_triangle_norm::certify(aa,bb,t,epsilon,ncc_triangle_norm::maximumDepth,maximumNodes,observer);
 const int detail=ok?NCC_DETAIL_NONE:(observer.reason==ncc_triangle_norm::Reason::nodeBudget||observer.reason==ncc_triangle_norm::Reason::depthBudget?NCC_DETAIL_PRECISION_OR_BUDGET:NCC_DETAIL_UNCERTAIN_GEOMETRY);
 return result(ok?NCC_SELF_CERT_CERTIFIED:NCC_SELF_CERT_UNCERTAIN,detail,observer.nodes,observer.depth);
}
extern "C" NCCSelfCertificateResult ncc_self_edge_certificate(const double*a,size_t ac,const double*b,size_t bc,double t){
 if(!valid(a,ac,b,bc,6,t))return result(NCC_SELF_CERT_INVALID,NCC_DETAIL_INVALID_ARGUMENT);
 if(!scale(a,b,6))return result(NCC_SELF_CERT_INVALID,NCC_DETAIL_UNSUPPORTED_SCALE);
 if(!ncc_triangle_norm::ieeeReady())return result(NCC_SELF_CERT_UNCERTAIN,ieeeDetail());
 const V e0=ncc_triangle_norm::difference(a+3,a),full=ncc_triangle_norm::difference(b+3,b);V end=full;
 if(t!=1)for(int i=0;i<3;++i)end[i]=ncc_triangle_norm::add(e0[i],ncc_triangle_norm::mul(ncc_triangle_norm::point(t),ncc_triangle_norm::sub(full[i],e0[i])));
 const I n0=ncc_triangle_norm::normSquared(e0),n1=ncc_triangle_norm::normSquared(end),projection=ncc_triangle_norm::dot(e0,end);
 if(!ncc_triangle_norm::finite(n0)||!ncc_triangle_norm::finite(n1)||!ncc_triangle_norm::finite(projection)||n0.lo<=1e-24||n1.lo<=1e-24)return result(NCC_SELF_CERT_UNCERTAIN,NCC_DETAIL_UNCERTAIN_GEOMETRY,1);
 const double lengthProduct=ncc_triangle_norm::up(std::sqrt(ncc_triangle_norm::up(n0.hi*n1.hi)));
 const double threshold=std::max(1e-24,ncc_triangle_norm::up(lengthProduct*1e-12));
 if(!std::isfinite(threshold)||projection.lo<=threshold)return result(NCC_SELF_CERT_UNCERTAIN,NCC_DETAIL_UNCERTAIN_GEOMETRY,1);
 // e0 dot e(s) is affine, strictly positive at BOTH endpoints; therefore no
 // linear edge can collapse anywhere in[0,t]. This adds no permissive fallback
 // to the existing primitive's original edge certificate.
 return result(NCC_SELF_CERT_CERTIFIED,NCC_DETAIL_NONE,1);
}
