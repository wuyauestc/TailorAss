// Independent test oracle: no NativeClothCollision, Tight-Inclusion, App model or production BVH.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>
struct V {double x,y,z;};
V operator+(V a,V b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
V operator-(V a,V b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
V operator*(V a,double t){return {a.x*t,a.y*t,a.z*t};}
double dot(V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;}
V cross(V a,V b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
V unit(V a){return a*(1/std::sqrt(dot(a,a)));}
struct Box {V lo,hi;};
struct T {V a,b,c; Box box;};
Box box(V a,V b,V c){return {{std::min({a.x,b.x,c.x}),std::min({a.y,b.y,c.y}),std::min({a.z,b.z,c.z})},
    {std::max({a.x,b.x,c.x}),std::max({a.y,b.y,c.y}),std::max({a.z,b.z,c.z})}};}
T tri(V a,V b,V c){return {a,b,c,box(a,b,c)};}
bool overlap(Box a,Box b,double e=1e-12){return a.lo.x<=b.hi.x+e&&a.hi.x+e>=b.lo.x&&
 a.lo.y<=b.hi.y+e&&a.hi.y+e>=b.lo.y&&a.lo.z<=b.hi.z+e&&a.hi.z+e>=b.lo.z;}
bool segmentTriangle(V a,V b,const T& t,double eps=1e-9,double* out=nullptr) {
 V d=b-a,e1=t.b-t.a,e2=t.c-t.a,h=cross(d,e2),s=a-t.a;
 double det=dot(e1,h);if(std::abs(det)<=1e-14)return false;
 double u=dot(s,h)/det,v=dot(d,cross(s,e1))/det,q=dot(e2,cross(s,e1))/det;
 if(u>eps&&v>eps&&u+v<1-eps&&q>eps&&q<1-eps){if(out)*out=q;return true;}return false;
}
struct P {double x,y;};
P project(V a,int drop){return drop==0?P{a.y,a.z}:(drop==1?P{a.z,a.x}:P{a.x,a.y});}
bool coplanarOverlap(const T&a,const T&b){
 V n=cross(a.b-a.a,a.c-a.a),m=cross(b.b-b.a,b.c-b.a);
 double nn=dot(n,n),mm=dot(m,m);if(nn==0||mm==0)return false;
 if(dot(cross(n,m),cross(n,m))>1e-20*nn*mm)return false;
 if(std::abs(dot(n,b.a-a.a))>1e-10*std::sqrt(nn))return false;
 int k=std::abs(n.x)>=std::abs(n.y)&&std::abs(n.x)>=std::abs(n.z)?0:(std::abs(n.y)>=std::abs(n.z)?1:2);
 std::array<P,3> p{project(a.a,k),project(a.b,k),project(a.c,k)},q{project(b.a,k),project(b.b,k),project(b.c,k)};
 // Strict separating-axis overlap catches identical/coincident triangles as well as partial overlap.
 for(const auto& polygon:std::array<std::array<P,3>,2>{p,q}) {
  for(int i=0;i<3;i++) {
   P edge{polygon[(i+1)%3].x-polygon[i].x,polygon[(i+1)%3].y-polygon[i].y};
   P axis{-edge.y,edge.x};
   auto range=[&](const std::array<P,3>&v){
    std::array<double,3> d{v[0].x*axis.x+v[0].y*axis.y,v[1].x*axis.x+v[1].y*axis.y,v[2].x*axis.x+v[2].y*axis.y};
    return std::array<double,2>{*std::min_element(d.begin(),d.end()),*std::max_element(d.begin(),d.end())};
   };
   auto u=range(p),v=range(q);
   double eps=1e-14*std::max({1.0,std::abs(u[0]),std::abs(u[1]),std::abs(v[0]),std::abs(v[1])});
   if(u[1]<=v[0]+eps||v[1]<=u[0]+eps)return false;
  }
 }
 return true;
}
bool crossing(const T&a,const T&b){
 std::array<V,3> p{a.a,a.b,a.c},q{b.a,b.b,b.c};
 for(int i=0;i<3;i++)if(segmentTriangle(p[i],p[(i+1)%3],b)||segmentTriangle(q[i],q[(i+1)%3],a))return true;
 return false;
}
struct RayData {V direction,u,v;std::vector<std::array<double,4>> bounds;std::vector<V> h;std::vector<double> inv;};
RayData prepareRay(V d,const std::vector<T>&body){
 RayData r;r.direction=unit(d);r.u=unit(cross(r.direction,{0,0,1}));r.v=cross(r.direction,r.u);
 for(auto t:body){
  auto pu=[&](V x){return dot(x,r.u);};auto pv=[&](V x){return dot(x,r.v);};
  r.bounds.push_back({std::min({pu(t.a),pu(t.b),pu(t.c)}),std::max({pu(t.a),pu(t.b),pu(t.c)}),
                     std::min({pv(t.a),pv(t.b),pv(t.c)}),std::max({pv(t.a),pv(t.b),pv(t.c)})});
  V h=cross(r.direction,t.c-t.a);double det=dot(t.b-t.a,h);
  r.h.push_back(h);r.inv.push_back(std::abs(det)>1e-14?1/det:0);
 }return r;
}
bool inside(V p,const std::vector<T>&body,const RayData&r){
 double u0=dot(p,r.u),v0=dot(p,r.v);std::vector<double> hits;
 for(size_t i=0;i<body.size();i++){
  auto bb=r.bounds[i];if(u0<bb[0]-1e-12||u0>bb[1]+1e-12||v0<bb[2]-1e-12||v0>bb[3]+1e-12||r.inv[i]==0)continue;
  auto t=body[i];V s=p-t.a,q=cross(s,t.b-t.a);
  double u=dot(s,r.h[i])*r.inv[i],v=dot(r.direction,q)*r.inv[i],time=dot(t.c-t.a,q)*r.inv[i];
  if(u>=-1e-10&&v>=-1e-10&&u+v<=1+1e-10&&time>1e-10)hits.push_back(time);
 }
 std::sort(hits.begin(),hits.end());int distinct=0;double prior=-1;
 for(double x:hits)if(prior<0||std::abs(x-prior)>1e-9*std::max(1.0,std::abs(x))){distinct++;prior=x;}
 return distinct%2==1;
}
struct Audit {size_t crossingPairs=0,coplanarPairs=0;std::vector<size_t> insideVertices,insideCentroids,ambiguousVertices,ambiguousCentroids;};
Audit audit(const std::vector<V>&p,const std::vector<uint32_t>&faces,const std::vector<T>&body,const std::vector<RayData>&rays){
 Audit a;
 auto classify=[&](V point,size_t id,bool centroid){
  int count=0;for(auto&r:rays)count+=inside(point,body,r);
  if(count==(int)rays.size())(centroid?a.insideCentroids:a.insideVertices).push_back(id);
  else if(count!=0)(centroid?a.ambiguousCentroids:a.ambiguousVertices).push_back(id);
 };
 for(size_t i=0;i<p.size();i++)classify(p[i],i,false);
 for(size_t i=0;i<faces.size()/3;i++){
  T t=tri(p[faces[3*i]],p[faces[3*i+1]],p[faces[3*i+2]]);
  classify((t.a+t.b+t.c)*(1.0/3),i,true);
  for(auto&b:body)if(overlap(t.box,b.box)){
   if(crossing(t,b))a.crossingPairs++;
   if(coplanarOverlap(t,b))a.coplanarPairs++;
  }
 }return a;
}
template<class T>void read(std::ifstream&f,T&v){f.read(reinterpret_cast<char*>(&v),sizeof(v));if(!f)throw std::runtime_error("input truncated");}
template<class T>std::vector<T> readArray(std::ifstream&f,size_t n){
 std::vector<T> a(n);f.read(reinterpret_cast<char*>(a.data()),n*sizeof(T));if(!f)throw std::runtime_error("input truncated");return a;
}
double edgeOracle(V a,V b,V da,V db,V c,V d){
 V u=b-a,du=db-da,v=d-c,w=a-c;
 double A=dot(da,cross(du,v)),B=dot(da,cross(u,v))+dot(w,cross(du,v)),C=dot(w,cross(u,v));
 std::vector<double> roots;
 if(std::abs(A)<1e-25){if(std::abs(B)>1e-25)roots.push_back(-C/B);}
 else {
  double disc=B*B-4*A*C;
  if(disc>=0){double q=-.5*(B+std::copysign(std::sqrt(disc),B));roots.push_back(q/A);if(q!=0)roots.push_back(C/q);}
 }
 double first=std::numeric_limits<double>::infinity();
 for(double t:roots){ if(t>=0&&t<=1){
  V aa=a+da*t,uu=(b+db*t)-aa,ww=aa-c;
  double U=dot(uu,uu),Vv=dot(v,v),UV=dot(uu,v),UW=dot(uu,ww),VW=dot(v,ww),den=U*Vv-UV*UV;
  if(den>0){double s=(UV*VW-Vv*UW)/den,r=(U*VW-UV*UW)/den;
   V delta=aa+uu*s-(c+v*r);
   if(s>=0&&s<=1&&r>=0&&r<=1&&dot(delta,delta)<1e-20)first=std::min(first,t);
  }
 }}
 return first;
}
void ids(const std::vector<size_t>&x){std::cout<<"[";for(size_t i=0;i<x.size();i++){if(i)std::cout<<",";std::cout<<x[i];}std::cout<<"]";}
void output(const Audit&a){
 std::cout<<"{\"interiorCrossingPairs\":"<<a.crossingPairs<<",\"coplanarOverlapPairs\":"<<a.coplanarPairs<<",\"insideVertices\":";ids(a.insideVertices);
 std::cout<<",\"insideCentroids\":";ids(a.insideCentroids);std::cout<<",\"ambiguousVertices\":";ids(a.ambiguousVertices);
 std::cout<<",\"ambiguousCentroids\":";ids(a.ambiguousCentroids);std::cout<<"}";
}
bool clean(const Audit&a){return a.crossingPairs==0&&a.coplanarPairs==0&&a.insideVertices.empty()&&a.insideCentroids.empty()&&a.ambiguousVertices.empty()&&a.ambiguousCentroids.empty();}
int main(int argc,char**argv){
 try{
  const T analytic=tri({-1,-1,0},{1,-1,0},{0,1,0});
  if(!coplanarOverlap(analytic,analytic))throw std::runtime_error("oracle identical coplanar failure");
  if(coplanarOverlap(analytic,tri({1,-1,0},{3,-1,0},{2,1,0})))throw std::runtime_error("oracle boundary-only contact failure");
  if(coplanarOverlap(analytic,tri({3,-1,0},{5,-1,0},{4,1,0})))throw std::runtime_error("oracle coplanar miss failure");
  if(!crossing(analytic,tri({0,-.2,-1},{0,.2,-1},{0,0,1})))throw std::runtime_error("oracle interior crossing failure");
  if(argc!=3)throw std::runtime_error("usage: oracle binary safeTime");
  double time=std::stod(argv[2]);if(!std::isfinite(time)||time<0||time>=1)throw std::runtime_error("unsafeTime");
  std::ifstream f(argv[1],std::ios::binary);char magic[8];f.read(magic,8);
  if(std::string(magic,5)!="NCCB1")throw std::runtime_error("format");
  uint32_t nv,nf,nc,nt;read(f,nv);read(f,nf);read(f,nc);read(f,nt);
  if(!nv||!nf||!nc||!nt||nv>1000000||nf>1000000||nc>1000000||nt>1000000)throw std::runtime_error("counts");
  auto bodyP=readArray<V>(f,nv);auto bodyF=readArray<uint32_t>(f,3*nf);
  auto before=readArray<V>(f,nc),candidate=readArray<V>(f,nc);auto clothF=readArray<uint32_t>(f,3*nt);auto witness=readArray<uint32_t>(f,4);
  for(auto i:bodyF)if(i>=nv)throw std::runtime_error("body index");for(auto i:clothF)if(i>=nc)throw std::runtime_error("cloth index");
  std::vector<T>body;for(uint32_t i=0;i<nf;i++)body.push_back(tri(bodyP[bodyF[3*i]],bodyP[bodyF[3*i+1]],bodyP[bodyF[3*i+2]]));
  std::vector<RayData>rays;for(V d:std::vector<V>{{1,.3713906763541037,.193847},{.2173913,1,.42105263},{.381966,.271828,1}})rays.push_back(prepareRay(d,body));
  std::vector<V>limited;for(size_t i=0;i<before.size();i++)limited.push_back(before[i]+(candidate[i]-before[i])*time);
  auto a=audit(before,clothF,body,rays),b=audit(candidate,clothF,body,rays),c=audit(limited,clothF,body,rays);
  size_t sweeps=0;
  for(size_t i=0;i<before.size();i++){
   Box bx=box(before[i],candidate[i],before[i]);
   for(auto&t:body)if(overlap(bx,t.box)&&segmentTriangle(before[i],candidate[i],t,1e-8))sweeps++;
  }
  double root=std::numeric_limits<double>::infinity();
  if(witness[0]<nc&&witness[1]<nc&&witness[2]<nv&&witness[3]<nv)
   root=edgeOracle(before[witness[0]],before[witness[1]],candidate[witness[0]]-before[witness[0]],candidate[witness[1]]-before[witness[1]],bodyP[witness[2]],bodyP[witness[3]]);
  bool passed=clean(a)&&clean(c)&&sweeps==99&&b.crossingPairs==626&&b.insideVertices.size()==99&&b.insideCentroids.size()==189&&b.ambiguousVertices.empty()&&b.ambiguousCentroids.empty()&&(!std::isfinite(root)||time<root);
  std::cout<<std::setprecision(17)<<"{\"passed\":"<<(passed?"true":"false")<<",\"safeTime\":"<<time<<",\"unrestrictedVertexSweeps\":"<<sweeps<<",\"independentWitnessEdgeTOI\":";
  if(std::isfinite(root))std::cout<<root;else std::cout<<"null";
  std::cout<<",\"before\":";output(a);std::cout<<",\"rawCandidate\":";output(b);std::cout<<",\"limited\":";output(c);
  std::cout<<",\"analyticOracleChecks\":4,\"method\":\"Independent full-scan triangle AABBs, bidirectional segment-triangle crossings, 2D coplanar overlap, 3-direction parity rays for every cloth vertex and face centroid; no production BVH or CCD used.\"}\n";
  return passed?0:1;
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 2;}
}

