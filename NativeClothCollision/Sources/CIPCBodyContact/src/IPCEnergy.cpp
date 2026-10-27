#include "IPCEnergy.h"
#include <ipc/barrier/barrier.hpp>
#include <ipc/distance/point_point.hpp>
#include <ipc/distance/point_edge.hpp>
#include <ipc/distance/edge_edge.hpp>
#include <ipc/distance/point_triangle.hpp>
#include <ipc/distance/edge_edge_mollifier.hpp>
#include <ipc/utils/eigen_ext.hpp>
#include <Eigen/Geometry>
#include <algorithm>
#include <cfenv>
#include <cmath>
#include <limits>
using V=Eigen::Vector3d;
namespace {
void invalid(IPCEnergyResult&out,int status){out.status=status;out.energy_joules=std::numeric_limits<double>::quiet_NaN();std::fill_n(out.gradient_newtons,12,std::numeric_limits<double>::quiet_NaN());std::fill_n(out.hessian_row_major_newtons_per_meter,144,std::numeric_limits<double>::quiet_NaN());}
bool triangleValid(const V&a,const V&b,const V&c){const V u=b-a,v=c-a;return u.cross(v).norm()>std::max(1e-24,std::max(u.squaredNorm(),v.squaredNorm())*1e-12);}
}
extern "C" size_t ipce_result_sizeof(void){return sizeof(IPCEnergyResult);}
extern "C" int ipce_evaluate_local(int kind,const double*xyz,size_t count,const double*rest,size_t restCount,int dtype,double w,double kappa,double dmin,double dhat,int mode,IPCEnergyResult*output){
 if(!output)return IPCE_INVALID;IPCEnergyResult&out=*output;out={};invalid(out,IPCE_INVALID);
 const int nv=kind==IPCE_VV?2:(kind==IPCE_EV?3:4),ndof=3*nv;
 if(kind<IPCE_VV||kind>IPCE_FV||!xyz||!rest||count!=size_t(ndof)||restCount!=count||!std::isfinite(w)||!std::isfinite(kappa)||kappa<=0||!std::isfinite(dmin)||dmin<0||!std::isfinite(dhat)||dhat<=0||mode<0||mode>2||std::fegetround()!=FE_TONEAREST)return out.status;
 for(size_t i=0;i<count;++i)if(!std::isfinite(xyz[i])||!std::isfinite(rest[i])||std::abs(xyz[i])>1e6||std::abs(rest[i])>1e6)return out.status;
 const int maximumType=kind==IPCE_VV?0:(kind==IPCE_EV?2:(kind==IPCE_EE?8:6));
 if(dtype<(-1)||dtype>maximumType)return out.status;
 V p[4],r[4];for(int i=0;i<nv;++i){p[i]=V(xyz[3*i],xyz[3*i+1],xyz[3*i+2]);r[i]=V(rest[3*i],rest[3*i+1],rest[3*i+2]);}
 if((kind==IPCE_EV&&(p[2]-p[1]).norm()<=1e-12)||(kind==IPCE_EE&&((p[1]-p[0]).norm()<=1e-12||(p[3]-p[2]).norm()<=1e-12))||(kind==IPCE_FV&&!triangleValid(p[1],p[2],p[3]))){invalid(out,IPCE_DEGENERATE);return out.status;}
 try {
  ipc::VectorMax12d gd(ndof);ipc::MatrixMax12d Hd(ndof,ndof);double d2=0;
  switch(kind){
  case IPCE_VV:dtype=0;d2=ipc::point_point_distance(p[0],p[1]);gd=ipc::point_point_distance_gradient(p[0],p[1]);Hd=ipc::point_point_distance_hessian(p[0],p[1]);break;
  case IPCE_EV:{auto t=dtype<0?ipc::point_edge_distance_type(p[0],p[1],p[2]):static_cast<ipc::PointEdgeDistanceType>(dtype);dtype=int(t);d2=ipc::point_edge_distance(p[0],p[1],p[2],t);gd=ipc::point_edge_distance_gradient(p[0],p[1],p[2],t);Hd=ipc::point_edge_distance_hessian(p[0],p[1],p[2],t);break;}
  case IPCE_EE:{auto t=dtype<0?ipc::edge_edge_distance_type(p[0],p[1],p[2],p[3]):static_cast<ipc::EdgeEdgeDistanceType>(dtype);dtype=int(t);d2=ipc::edge_edge_distance(p[0],p[1],p[2],p[3],t);gd=ipc::edge_edge_distance_gradient(p[0],p[1],p[2],p[3],t);Hd=ipc::edge_edge_distance_hessian(p[0],p[1],p[2],p[3],t);break;}
  case IPCE_FV:{auto t=dtype<0?ipc::point_triangle_distance_type(p[0],p[1],p[2],p[3]):static_cast<ipc::PointTriangleDistanceType>(dtype);dtype=int(t);d2=ipc::point_triangle_distance(p[0],p[1],p[2],p[3],t);gd=ipc::point_triangle_distance_gradient(p[0],p[1],p[2],p[3],t);Hd=ipc::point_triangle_distance_hessian(p[0],p[1],p[2],p[3],t);break;}
  }
  out.dof_count=ndof;out.distance_type=dtype;out.hessian_mode=mode;out.distance_squared_m2=d2;
  if(!std::isfinite(d2)||d2<0||!gd.allFinite()||!Hd.allFinite()){invalid(out,IPCE_NUMERICAL);return out.status;}
  const double q=d2-dmin*dmin,Q=(2*dmin+dhat)*dhat;
  if(q<=0){invalid(out,IPCE_INFEASIBLE);return out.status;}
  if(!std::isfinite(Q)||Q<=0){invalid(out,IPCE_NUMERICAL);return out.status;}
  double m=1,threshold=0;ipc::VectorMax12d gm=ipc::VectorMax12d::Zero(ndof);ipc::MatrixMax12d Hm=ipc::MatrixMax12d::Zero(ndof,ndof);
  if(kind==IPCE_EE){threshold=ipc::edge_edge_mollifier_threshold(r[0],r[1],r[2],r[3]);if(!std::isfinite(threshold)||threshold<=0){invalid(out,IPCE_DEGENERATE);return out.status;}m=ipc::edge_edge_mollifier(p[0],p[1],p[2],p[3],threshold);gm=ipc::edge_edge_mollifier_gradient(p[0],p[1],p[2],p[3],threshold);Hm=ipc::edge_edge_mollifier_hessian(p[0],p[1],p[2],p[3],threshold);}
  const double scale=kappa*dhat/(Q*Q),f=scale*ipc::barrier(q,Q),fp=scale*ipc::barrier_first_derivative(q,Q),fpp=scale*ipc::barrier_second_derivative(q,Q);
  ipc::VectorMax12d g=w*(f*gm+m*fp*gd);ipc::MatrixMax12d H=w*(f*Hm+fp*(gm*gd.transpose()+gd*gm.transpose())+m*fpp*gd*gd.transpose()+m*fp*Hd);
  const double energy=w*m*f;
  if(!std::isfinite(energy)||!g.allFinite()||!H.allFinite()){invalid(out,IPCE_NUMERICAL);return out.status;}
  if(mode!=IPCE_RAW_HESSIAN)H=ipc::project_to_psd(H,mode==IPCE_CLAMP_PSD?ipc::PSDProjectionMethod::CLAMP:ipc::PSDProjectionMethod::ABS);
  out.status=IPCE_OK;out.energy_joules=energy;out.mollifier=m;out.mollifier_threshold_m4=threshold;std::fill_n(out.gradient_newtons,12,0.);std::fill_n(out.hessian_row_major_newtons_per_meter,144,0.);
  for(int i=0;i<ndof;++i){out.gradient_newtons[i]=g[i];for(int j=0;j<ndof;++j)out.hessian_row_major_newtons_per_meter[i*ndof+j]=H(i,j);}
  return out.status;
 }catch(...){invalid(out,IPCE_NUMERICAL);return out.status;}
}
