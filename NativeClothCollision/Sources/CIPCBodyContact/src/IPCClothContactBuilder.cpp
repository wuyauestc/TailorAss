// Research all-moving serial translation of ipc-toolkit v1.6.1 signed improved-max builder.
// Primitive-ID adjacency matches official BroadPhase.cpp; no panel/sewing exclusions.
// MIT original equations/algorithm: ipc-sim/ipc-toolkit, pinned 19bcab7e1f5a0d2addfcd28513422ff248ea504e.
#include "IPCClothContactBuilder.h"
#include "IPCOrientedEdgeKey.hpp"
#include <ipc/distance/point_point.hpp>
#include <ipc/distance/point_edge.hpp>
#include <ipc/distance/edge_edge.hpp>
#include <ipc/distance/point_triangle.hpp>
#include <ipc/distance/edge_edge_mollifier.hpp>
#include <Eigen/Geometry>
#include <array>
#include <vector>
#include <set>
#include <map>
#include <algorithm>
#include <cmath>
#include <cfenv>
#include <limits>
#include <stdexcept>
using V=Eigen::Vector3d;using Edge=std::array<uint32_t,2>;using Face=std::array<uint32_t,3>;
struct IPCCPrepared{
 size_t nv,maxc,maxs;std::vector<V>rest;std::vector<Edge>edges;std::vector<Face>faces,fe;
 std::vector<std::set<uint32_t>>ve,vv,ev;std::vector<bool>boundary;std::vector<double>va,ea;
};
namespace {
struct Abort{int status;};
struct Work{IPCCCancel cancel;void*context;size_t n=0;void tick(){if((n++%32)==0&&cancel&&cancel(context))throw Abort{5};}};
Edge ordered(uint32_t a,uint32_t b){return {std::min(a,b),std::max(a,b)};}
struct S{int kind,a,b,dtype;double w;};
using Key=std::array<int,4>;
struct Run{
 const IPCCPrepared&p;std::vector<V>x;double kappa,dmin,h,minimum=std::numeric_limits<double>::infinity();int mode;Work work;std::map<Key,S>st;size_t candidates=0;
 Run(const IPCCPrepared&_p,const double*xyz,double k,double d,double hh,int mm,IPCCCancel c,void*ctx):p(_p),kappa(k),dmin(d),h(hh),mode(mm),work{c,ctx}{x.reserve(p.nv);for(size_t i=0;i<p.nv;++i){work.tick();x.emplace_back(xyz[3*i],xyz[3*i+1],xyz[3*i+2]);if(!x.back().allFinite()||x.back().cwiseAbs().maxCoeff()>1e6)throw Abort{IPCE_INVALID};}}
 bool active(double d){if(!std::isfinite(d)||d<0)throw Abort{IPCE_NUMERICAL};minimum=std::min(minimum,std::sqrt(d));if(d<=dmin*dmin)throw Abort{IPCE_INFEASIBLE};return d<(dmin+h)*(dmin+h);}
 bool overlap(const std::vector<uint32_t>&a,const std::vector<uint32_t>&b){V al=x[a[0]],au=al,bl=x[b[0]],bu=bl;for(auto v:a){al=al.cwiseMin(x[v]);au=au.cwiseMax(x[v]);}for(auto v:b){bl=bl.cwiseMin(x[v]);bu=bu.cwiseMax(x[v]);}double R=dmin+h;return (al.array()<=bu.array()+R).all()&&(bl.array()<=au.array()+R).all();}
 void add(int k,int a,int b,double w,int dtype=-1){if(k==2)ipc_serial::canonicalize_edge_pair(a,b,dtype);Key key={k,a,b,dtype};if(k==0){key[1]=std::min(a,b);key[2]=std::max(a,b);}if(k!=2)key[3]=-1;auto it=st.find(key);if(it!=st.end())it->second.w+=w;else{if(st.size()>=p.maxs)throw Abort{6};st.emplace(key,S{k,a,b,dtype,w});}}
 void pe(int e,int v,int t,double w){if(t<2)add(0,v,p.edges[e][t],w);else add(1,e,v,w);}
 double pd(int e,int v)const{auto a=p.edges[e];return ipc::point_edge_distance(x[v],x[a[0]],x[a[1]]);}
 int pt(int e,int v)const{auto a=p.edges[e];return int(ipc::point_edge_distance_type(x[v],x[a[0]],x[a[1]]));}
 double eps(int a,int b)const{auto ea=p.edges[a],eb=p.edges[b];return ipc::edge_edge_mollifier_threshold(p.rest[ea[0]],p.rest[ea[1]],p.rest[eb[0]],p.rest[eb[1]]);}
 double cross(int a,int b)const{auto ea=p.edges[a],eb=p.edges[b];return ipc::edge_edge_cross_squarednorm(x[ea[0]],x[ea[1]],x[eb[0]],x[eb[1]]);}
 void ee(int a,int b){work.tick();auto ea=p.edges[a],eb=p.edges[b];auto at=ipc::edge_edge_distance_type(x[ea[0]],x[ea[1]],x[eb[0]],x[eb[1]]);double d=ipc::edge_edge_distance(x[ea[0]],x[ea[1]],x[eb[0]],x[eb[1]],at);if(!active(d))return;int t=cross(a,b)<eps(a,b)?8:int(at);double w=.25*(p.ea[a]+p.ea[b]);if(t<4)add(0,ea[t/2],eb[t%2],w);else if(t<6)add(1,a,eb[t-4],w);else if(t<8)add(1,b,ea[t-6],w);else add(2,a,b,w,int(at));}
 void fv(int f,int v){work.tick();auto a=p.faces[f];auto t=ipc::point_triangle_distance_type(x[v],x[a[0]],x[a[1]],x[a[2]]);if(!active(ipc::point_triangle_distance(x[v],x[a[0]],x[a[1]],x[a[2]],t)))return;double w=.25*p.va[v];int it=int(t);if(it<3)add(0,v,a[it],w);else if(it<6)add(1,p.fe[f][it-3],v,w);else add(3,f,v,w);}
 void negativeEEEV(int a,int v){work.tick();auto ea=p.edges[a];int t=pt(a,v);double w=-.25*p.ea[a];size_t count=0;for(auto b:p.ve[v]){auto eb=p.edges[b];uint32_t q=eb[uint32_t(v==eb[0])];if(q==ea[0]||q==ea[1])continue;if(cross(a,b)>=eps(a,b)){++count;continue;}int dt=t==0?(v==int(eb[0])?0:1):(t==1?(v==int(eb[0])?2:3):(v==int(eb[0])?4:5));add(2,a,b,w,dt);}if(count!=1)pe(a,v,t,(double(count)-1)*w);}
 std::array<uint32_t,4>ids(const S&s)const{if(s.kind==0)return {uint32_t(s.a),uint32_t(s.b),0,0};if(s.kind==1){auto e=p.edges[s.a];return {uint32_t(s.b),e[0],e[1],0};}if(s.kind==2){auto a=p.edges[s.a],b=p.edges[s.b];return {a[0],a[1],b[0],b[1]};}auto f=p.faces[s.a];return {uint32_t(s.b),f[0],f[1],f[2]};}
 void build(const IPCCFacePair*input,size_t n){
  if(n>p.maxc)throw Abort{6};std::set<Edge>eeC,fvC;std::set<Edge>pairs;
  for(size_t i=0;i<n;++i){work.tick();auto a=input[i].face0,b=input[i].face1;if(a>=p.faces.size()||b>=p.faces.size()||a==b)throw Abort{IPCE_INVALID};pairs.insert(ordered(a,b));}
  auto budget=[&]{if(eeC.size()+fvC.size()>p.maxc)throw Abort{6};};
  for(auto pair:pairs){work.tick();auto a=pair[0],b=pair[1];for(auto v:p.faces[a])if(std::find(p.faces[b].begin(),p.faces[b].end(),v)==p.faces[b].end()&&overlap({p.faces[b][0],p.faces[b][1],p.faces[b][2]},{v})){fvC.insert({b,v});budget();}for(auto v:p.faces[b])if(std::find(p.faces[a].begin(),p.faces[a].end(),v)==p.faces[a].end()&&overlap({p.faces[a][0],p.faces[a][1],p.faces[a][2]},{v})){fvC.insert({a,v});budget();}for(auto ea:p.fe[a])for(auto eb:p.fe[b])if(p.edges[ea][0]!=p.edges[eb][0]&&p.edges[ea][0]!=p.edges[eb][1]&&p.edges[ea][1]!=p.edges[eb][0]&&p.edges[ea][1]!=p.edges[eb][1]&&overlap({p.edges[ea][0],p.edges[ea][1]},{p.edges[eb][0],p.edges[eb][1]})){eeC.insert(ordered(ea,eb));budget();}}
  candidates=eeC.size()+fvC.size();for(auto a:eeC)ee(a[0],a[1]);for(auto a:fvC)fv(a[0],a[1]);
  std::set<Edge>eev,fev,fvv;
  for(auto a:eeC)for(int i=0;i<2;++i){auto e=a[i],other=a[1-i];for(auto v:p.edges[other]){work.tick();if(active(pd(e,v)))eev.insert({e,v});}}
  for(auto a:eev)negativeEEEV(a[0],a[1]);
  for(auto a:fvC){auto f=a[0],v=a[1];for(auto e:p.fe[f]){work.tick();if(active(pd(e,v)))fev.insert({e,v});}for(auto q:p.faces[f])if(active(ipc::point_point_distance(x[v],x[q])))fvv.insert(ordered(v,q));}
  for(auto a:fev){work.tick();auto e=a[0],v=a[1];size_t incident=p.ev[e].size()-p.ev[e].count(v);if(incident>1)pe(e,v,pt(e,v),(1-double(incident))*.25*p.va[v]);}
  for(auto a:fvv){work.tick();double w=0.;for(int i=0;i<2;++i){auto v=a[i],q=a[1-i];if(!p.boundary[q]&&!p.vv[q].count(v))w+=.25*p.va[v];}if(w!=0)add(0,a[0],a[1],w);}
  for(auto it=st.begin();it!=st.end();)if(it->second.w==0)it=st.erase(it);else ++it;
 }
 IPCCBlock local(const S&s){IPCCBlock block{};block.kind=s.kind;block.num_vertices=s.kind==0?2:(s.kind==1?3:4);block.distance_type=s.dtype;auto ii=ids(s);double xx[12]{},rr[12]{};for(int j=0;j<block.num_vertices;++j){block.vertex_ids[j]=ii[j];for(int k=0;k<3;++k){xx[3*j+k]=x[ii[j]][k];rr[3*j+k]=p.rest[ii[j]][k];}}block.signed_rest_area_m2=s.w;int status=ipce_evaluate_local(s.kind,xx,3*block.num_vertices,rr,3*block.num_vertices,s.dtype,s.w,kappa,dmin,h,mode,&block.local);if(status)throw Abort{status};return block;}
};
}
extern "C" IPCCPrepared*ipcc_create(const double*rest,size_t nv,const uint32_t*tri,size_t nf,size_t maxc,size_t maxs,IPCCCancel cancelled,void*ctx,int*out_status){
 if(out_status)*out_status=IPCE_INVALID;
 if(!out_status||!rest||!tri||nv<3||nv>20000||nf==0||nf>40000||maxc==0||maxc>200000||maxs==0||maxs>200000||std::fegetround()!=FE_TONEAREST)return nullptr;
 IPCCPrepared*p=nullptr;try{Work w{cancelled,ctx};w.tick();p=new IPCCPrepared;p->nv=nv;p->maxc=maxc;p->maxs=maxs;p->rest.reserve(nv);p->faces.reserve(nf);p->va.assign(nv,0);p->ve.resize(nv);p->vv.resize(nv);p->boundary.assign(nv,true);std::map<Edge,uint32_t>lookup;std::set<Face>uniqueFaces;
 for(size_t i=0;i<nv;++i){w.tick();p->rest.emplace_back(rest[3*i],rest[3*i+1],rest[3*i+2]);if(!p->rest.back().allFinite()||p->rest.back().cwiseAbs().maxCoeff()>1e6)throw Abort{IPCE_INVALID};}
 for(size_t i=0;i<nf;++i){w.tick();Face f={tri[3*i],tri[3*i+1],tri[3*i+2]},key=f;std::sort(key.begin(),key.end());if(key[0]==key[1]||key[1]==key[2]||key[2]>=nv||!uniqueFaces.insert(key).second)throw Abort{IPCE_INVALID};p->faces.push_back(f);for(int j=0;j<3;++j)lookup.emplace(ordered(f[j],f[(j+1)%3]),0);}
 if(lookup.size()>60000)throw Abort{6};for(auto&item:lookup){item.second=p->edges.size();p->edges.push_back(item.first);}p->ea.assign(p->edges.size(),0);p->ev.resize(p->edges.size());
 for(uint32_t i=0;i<p->edges.size();++i){auto e=p->edges[i];p->ve[e[0]].insert(i);p->ve[e[1]].insert(i);p->vv[e[0]].insert(e[1]);p->vv[e[1]].insert(e[0]);}
 for(auto f:p->faces){w.tick();double area=.5*(p->rest[f[1]]-p->rest[f[0]]).cross(p->rest[f[2]]-p->rest[f[0]]).norm();if(!std::isfinite(area)||area<=1e-18)throw Abort{IPCE_DEGENERATE};Face row{};for(int j=0;j<3;++j){auto e=lookup.at(ordered(f[j],f[(j+1)%3]));row[j]=e;p->ev[e].insert(f[(j+2)%3]);p->va[f[j]]+=area/3;p->ea[e]+=area/3;}p->fe.push_back(row);}
 for(size_t i=0;i<nv;++i)if(p->va[i]<=0)throw Abort{7};for(size_t e=0;e<p->edges.size();++e)if(p->ev[e].size()>=2)for(auto v:p->edges[e])p->boundary[v]=false;
 *out_status=IPCE_OK;return p;
 }catch(const Abort&e){delete p;*out_status=e.status;return nullptr;}catch(...){delete p;*out_status=IPCE_NUMERICAL;return nullptr;}}
extern "C" void ipcc_destroy(IPCCPrepared*p){delete p;}
extern "C" int ipcc_evaluate(const IPCCPrepared*p,const double*xyz,size_t n,const IPCCFacePair*pairs,size_t pairCount,double kappa,double dmin,double h,int mode,double*gradient,size_t ng,IPCCBlockConsumer consume,void*consumerContext,IPCCCancel cancel,void*cancelContext,IPCCResult*out){
 if(!out)return IPCE_INVALID;*out={};out->status=IPCE_INVALID;out->energy_joules=std::numeric_limits<double>::quiet_NaN();out->minimum_candidate_distance_meters=std::numeric_limits<double>::quiet_NaN();
 if(!p||!xyz||n!=3*p->nv||(pairCount&&!pairs)||!gradient||ng!=3*p->nv||!std::isfinite(kappa)||kappa<=0||!std::isfinite(dmin)||dmin<0||!std::isfinite(h)||h<=0||mode<0||mode>2||std::fegetround()!=FE_TONEAREST)return out->status;
 try{Run run(*p,xyz,kappa,dmin,h,mode,cancel,cancelContext);run.build(pairs,pairCount);std::fill_n(gradient,ng,0.);double energy=0.;out->candidate_count=run.candidates;out->stencil_count=run.st.size();
 for(const auto&item:run.st){run.work.tick();const S&s=item.second;auto b=run.local(s);energy+=b.local.energy_joules;out->negative_stencil_count+=s.w<0;if(s.kind==0)++out->vv_count;else if(s.kind==1)++out->ev_count;else if(s.kind==2)++out->ee_count;else ++out->fv_count;for(int j=0;j<b.num_vertices;++j)for(int k=0;k<3;++k)gradient[3*b.vertex_ids[j]+k]+=b.local.gradient_newtons[3*j+k];}
 if(!std::isfinite(energy))throw Abort{IPCE_NUMERICAL};for(size_t i=0;i<ng;++i)if(!std::isfinite(gradient[i]))throw Abort{IPCE_NUMERICAL};if(consume)for(const auto&item:run.st){run.work.tick();auto block=run.local(item.second);consume(&block,consumerContext);}
 out->energy_joules=energy;out->minimum_candidate_distance_meters=run.minimum;out->status=IPCE_OK;return out->status;
 }catch(const Abort&e){std::fill_n(gradient,ng,std::numeric_limits<double>::quiet_NaN());out->status=e.status;return out->status;}catch(...){std::fill_n(gradient,ng,std::numeric_limits<double>::quiet_NaN());out->status=IPCE_NUMERICAL;return out->status;}}
