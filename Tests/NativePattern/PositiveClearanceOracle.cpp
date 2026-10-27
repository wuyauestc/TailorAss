// Independent sampled geometry oracle; no production or third-party dependency.
#include <vector>
#include <array>
#include <map>
#include <tuple>
#include <algorithm>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <chrono>
#include <stdexcept>
#include <cmath>
#include <limits>
struct V {
 long double c[3]{};
 V()=default;V(long double x,long double y,long double z):c{x,y,z}{}
 long double&operator[](int i){return c[i];}long double operator[](int i)const{return c[i];}
 V operator+(const V&o)const{return {c[0]+o[0],c[1]+o[1],c[2]+o[2]};}
 V operator-(const V&o)const{return {c[0]-o[0],c[1]-o[1],c[2]-o[2]};}
 V operator*(long double t)const{return {c[0]*t,c[1]*t,c[2]*t};}
 V cwiseMin(const V&o)const{return {std::min(c[0],o[0]),std::min(c[1],o[1]),std::min(c[2],o[2])};}
 V cwiseMax(const V&o)const{return {std::max(c[0],o[0]),std::max(c[1],o[1]),std::max(c[2],o[2])};}
 void maxCoeff(int*axis)const{*axis=0;for(int i=1;i<3;++i)if(c[i]>c[*axis])*axis=i;}
 bool allFinite()const{return std::isfinite(c[0])&&std::isfinite(c[1])&&std::isfinite(c[2]);}
};
using Face=std::array<int,3>;using Edge=std::array<int,2>;
namespace independent {
long double dot(V a,V b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
long double pointSegment(V p,V a,V b){V e=b-a,r=p-a;long double ee=dot(e,e);if(ee<=0)throw std::runtime_error("degenerate independent edge");long double t=std::clamp(dot(r,e)/ee,0.L,1.L);V d=p-(a+e*t);return dot(d,d);}
// Plane projection with an independent Gram solve; outside projects to all three
// boundary segments. This differs from production's Voronoi-region algorithm.
long double pointTriangle(V p,V a,V b,V c){V u=b-a,v=c-a,r=p-a;long double uu=dot(u,u),uv=dot(u,v),vv=dot(v,v),ru=dot(r,u),rv=dot(r,v),D=uu*vv-uv*uv;if(D<=0)throw std::runtime_error("degenerate independent triangle");long double s=(ru*vv-rv*uv)/D,t=(rv*uu-ru*uv)/D;if(s>=0&&t>=0&&s+t<=1){V q=r-u*s-v*t;return dot(q,q);}return std::min({pointSegment(p,a,b),pointSegment(p,b,c),pointSegment(p,c,a)});}
// Interior line-line solution plus all four endpoint/segment minima. Parallel
// lines are handled by endpoint/segment tests, including overlapping intervals.
long double edgeEdge(V a,V b,V c,V d){V u=b-a,v=d-c,r=a-c;long double aa=dot(u,u),ee=dot(v,v),bb=dot(u,v),cc=dot(u,r),ff=dot(v,r),D=aa*ee-bb*bb;long double best=std::min({pointSegment(a,c,d),pointSegment(b,c,d),pointSegment(c,a,b),pointSegment(d,a,b)});if(D>0){long double s=(bb*ff-cc*ee)/D,t=(aa*ff-bb*cc)/D;if(s>=0&&s<=1&&t>=0&&t<=1){V q=r+u*s-v*t;best=std::min(best,dot(q,q));}}return best;}
}
struct Box{V lo,hi;};
Box combine(Box a,Box b){return {a.lo.cwiseMin(b.lo),a.hi.cwiseMax(b.hi)};}
double lower(Box a,Box b){double s=0;for(int k=0;k<3;++k){long double d=std::max({a.lo[k]-b.hi[k],b.lo[k]-a.hi[k],0.L});s+=d*d;}return s;}
struct Node{Box box;int l=-1,r=-1,begin=0,end=0;};
struct Tree{std::vector<Box>boxes;std::vector<int>order;std::vector<Node>nodes;
 Tree(std::vector<Box>b,std::vector<int>ids):boxes(std::move(b)),order(std::move(ids)){if(order.empty())throw std::runtime_error("empty panel tree");build(0,int(order.size()));}
 int build(int begin,int end){if(nodes.size()>100000)throw std::runtime_error("BVH nodes budget");Box b=boxes[order[begin]];for(int i=begin+1;i<end;++i)b=combine(b,boxes[order[i]]);int id=nodes.size();nodes.push_back({b,-1,-1,begin,end});if(end-begin<=8)return id;int axis=0;(b.hi-b.lo).maxCoeff(&axis);int mid=(begin+end)/2;std::nth_element(order.begin()+begin,order.begin()+mid,order.begin()+end,[&](int a,int bb){double x=boxes[a].lo[axis]+boxes[a].hi[axis],y=boxes[bb].lo[axis]+boxes[bb].hi[axis];return x==y?a<bb:x<y;});int l=build(begin,mid),r=build(mid,end);nodes[id].l=l;nodes[id].r=r;return id;}
 template<class F>void within(Box b,double maximum,F&&f,size_t&visits)const{std::vector<int>stack{0};while(!stack.empty()){if(++visits>100000000)throw std::runtime_error("query visit budget");int i=stack.back();stack.pop_back();auto n=nodes[i];if(lower(b,n.box)>maximum)continue;if(n.l<0){for(int k=n.begin;k<n.end;++k)if(lower(b,boxes[order[k]])<=maximum)f(order[k]);}else{stack.push_back(n.r);stack.push_back(n.l);}}}
 template<class F>void nearest(Box b,double&best,F&&f,size_t&visits)const{std::vector<int>stack{0};while(!stack.empty()){if(++visits>100000000)throw std::runtime_error("query visit budget");int i=stack.back();stack.pop_back();auto n=nodes[i];if(lower(b,n.box)>=best)continue;if(n.l<0){for(int k=n.begin;k<n.end;++k)if(lower(b,boxes[order[k]])<best)f(order[k],best);}else{double a=lower(b,nodes[n.l].box),bb=lower(b,nodes[n.r].box);if(a<bb){stack.push_back(n.r);stack.push_back(n.l);}else{stack.push_back(n.l);stack.push_back(n.r);}}}}
};
struct Feature{int kind,dtype;std::array<int,4>ids;int face=-1,edgeA=-1,edgeB=-1;double d2;};
void feature(std::ostream&o,const Feature&f){o<<"{\"kind\":\""<<(f.kind==0?"VF":"EE")<<"\",\"ids\":[";for(int i=0;i<4;++i){if(i)o<<',';o<<f.ids[i];}o<<"],\"distanceMeters\":"<<std::sqrt(f.d2)<<",\"distanceSquaredMeters2\":"<<f.d2<<",\"exactDoubleZero\":"<<(f.d2==0?"true":"false")<<",\"dtype\":"<<f.dtype<<",\"faceID\":"<<f.face<<",\"edgeIDs\":["<<f.edgeA<<','<<f.edgeB<<"]}";}
struct Pair{int a,b;double vf=INFINITY,ee=INFINITY;Feature fv{},fe{};std::vector<Feature>near;size_t vfZero=0,eeZero=0,vfNear=0,eeNear=0,adjSkip=0,visits=0;};
int main(int argc,char**argv){try{if(argc!=3)throw std::runtime_error("input output");std::ifstream in(argv[1]);std::ofstream out(argv[2]);out<<std::setprecision(17);std::string magic;int cases;in>>magic>>cases;if(magic!="SELFBOOT1"||cases<=0||cases>211)throw std::runtime_error("header");out<<"{\"longDoubleMantissaBits\":"<<std::numeric_limits<long double>::digits<<",\"doubleMantissaBits\":"<<std::numeric_limits<double>::digits<<",\"scope\":\"Read-only cross-panel strict positive-distance initialization screen; independent long-double Gram/line-boundary oracle (not production distance code), no physics\",\"toleranceMeters\":1e-8,\"cases\":[";
 for(int caseid=0;caseid<cases;++caseid){auto start=std::chrono::steady_clock::now();std::string name;int nv,nf,np;in>>name>>nv>>nf>>np;if(nv<1||nv>20000||nf<1||nf>40000||np<1||np>100)throw std::runtime_error("source budget");std::vector<std::string>names(np);for(auto&s:names)in>>s;std::vector<V>x(nv);std::vector<int>vp(nv),fp(nf);std::vector<Face>faces(nf);std::vector<std::vector<int>>vertices(np),triangles(np),edgesByPanel(np);for(int i=0;i<nv;++i){double xx,yy,zz;in>>xx>>yy>>zz>>vp[i];x[i]=V(xx,yy,zz);if(!x[i].allFinite()||vp[i]<0||vp[i]>=np)throw std::runtime_error("bad vertex");vertices[vp[i]].push_back(i);}std::map<Edge,int>emap;for(int i=0;i<nf;++i){in>>faces[i][0]>>faces[i][1]>>faces[i][2]>>fp[i];auto f=faces[i];if(fp[i]<0||fp[i]>=np)throw std::runtime_error("face panel");for(auto v:f)if(v<0||v>=nv||vp[v]!=fp[i])throw std::runtime_error("face ownership");triangles[fp[i]].push_back(i);for(int j=0;j<3;++j){Edge e={std::min(f[j],f[(j+1)%3]),std::max(f[j],f[(j+1)%3])};emap.emplace(e,0);}}if(!in)throw std::runtime_error("input parse");std::vector<Edge>edges;for(auto&[e,id]:emap){id=edges.size();edges.push_back(e);edgesByPanel[vp[e[0]]].push_back(id);}std::vector<Box>fbox(nf),ebox(edges.size());for(int i=0;i<nf;++i){auto f=faces[i];fbox[i]={x[f[0]].cwiseMin(x[f[1]]).cwiseMin(x[f[2]]),x[f[0]].cwiseMax(x[f[1]]).cwiseMax(x[f[2]])};}for(size_t i=0;i<edges.size();++i){auto e=edges[i];ebox[i]={x[e[0]].cwiseMin(x[e[1]]),x[e[0]].cwiseMax(x[e[1]])};}
 std::vector<Tree>ft,et;for(int i=0;i<np;++i){ft.emplace_back(fbox,triangles[i]);et.emplace_back(ebox,edgesByPanel[i]);}
 size_t totalNear=0;std::vector<Pair>pairs;
 auto checked=[](double d){if(!std::isfinite(d)||d<0)throw std::runtime_error("nonfinite/negative original primitive distance");return d;};
 for(int a=0;a<np;++a)for(int b=a;b<np;++b){Pair pair;pair.a=a;pair.b=b;
  for(int direction=0;direction<2;++direction){if(a==b&&direction==1)continue;int from=direction?b:a,to=direction?a:b;for(auto v:vertices[from]){Box box{x[v],x[v]};auto dist=[&](int f){auto q=faces[f];int t=-1;double d=checked(double(independent::pointTriangle(x[v],x[q[0]],x[q[1]],x[q[2]])));return Feature{0,t,{v,q[0],q[1],q[2]},f,-1,-1,d};};auto adjacent=[&](int f){auto q=faces[f];return v==q[0]||v==q[1]||v==q[2];};ft[to].nearest(box,pair.vf,[&](int f,double&best){if(adjacent(f)){++pair.adjSkip;return;}auto hit=dist(f);if(hit.d2<best){best=hit.d2;pair.fv=hit;}},pair.visits);ft[to].within(box,1e-16,[&](int f){if(adjacent(f)){++pair.adjSkip;return;}auto hit=dist(f);if(hit.d2<=1e-16){pair.near.push_back(hit);++pair.vfNear;pair.vfZero+=hit.d2==0;if(++totalNear>1000000)throw std::runtime_error("near feature budget");}},pair.visits);}}
  for(auto ea:edgesByPanel[a]){auto e=edges[ea];auto dist=[&](int eb){auto f=edges[eb];int t=-1;double d=checked(double(independent::edgeEdge(x[e[0]],x[e[1]],x[f[0]],x[f[1]])));return Feature{1,t,{e[0],e[1],f[0],f[1]},-1,ea,eb,d};};auto adjacent=[&](int eb){if(a==b&&eb<=ea)return true;auto f=edges[eb];return e[0]==f[0]||e[0]==f[1]||e[1]==f[0]||e[1]==f[1];};et[b].nearest(ebox[ea],pair.ee,[&](int eb,double&best){if(adjacent(eb)){++pair.adjSkip;return;}auto hit=dist(eb);if(hit.d2<best){best=hit.d2;pair.fe=hit;}},pair.visits);et[b].within(ebox[ea],1e-16,[&](int eb){if(adjacent(eb)){++pair.adjSkip;return;}auto hit=dist(eb);if(hit.d2<=1e-16){pair.near.push_back(hit);++pair.eeNear;pair.eeZero+=hit.d2==0;if(++totalNear>1000000)throw std::runtime_error("near feature budget");}},pair.visits);}
  pairs.push_back(std::move(pair));
 }
 // Exact coordinate coincidences are independent source IDs, never adjacency.
 std::map<std::tuple<double,double,double>,std::vector<int>>coincident;for(int i=0;i<nv;++i)coincident[{x[i][0],x[i][1],x[i][2]}].push_back(i);std::vector<Edge>same;for(auto&[_,ids]:coincident)for(size_t i=0;i<ids.size();++i)for(size_t j=i+1;j<ids.size();++j)if(vp[ids[i]]!=vp[ids[j]])same.push_back({ids[i],ids[j]});
 double minimumVF=INFINITY,minimumEE=INFINITY;size_t vfNear=0,eeNear=0,vfZero=0,eeZero=0;for(auto&p:pairs){minimumVF=std::min(minimumVF,p.vf);minimumEE=std::min(minimumEE,p.ee);vfNear+=p.vfNear;eeNear+=p.eeNear;vfZero+=p.vfZero;eeZero+=p.eeZero;}
 if(caseid)out<<',';out<<"{\"case\":\""<<name<<"\",\"vertices\":"<<nv<<",\"triangles\":"<<nf<<",\"edges\":"<<edges.size()<<",\"panels\":"<<np<<",\"minimumVFDistanceMeters\":"<<std::sqrt(minimumVF)<<",\"minimumEEDistanceMeters\":"<<std::sqrt(minimumEE)<<",\"nearVF\":"<<vfNear<<",\"nearEE\":"<<eeNear<<",\"exactZeroVF\":"<<vfZero<<",\"exactZeroEE\":"<<eeZero<<",\"exactCoincidentIndependentVertexPairs\":[";for(size_t i=0;i<same.size();++i){if(i)out<<',';out<<'['<<same[i][0]<<','<<same[i][1]<<']';}out<<"],\"pairs\":[";
 for(size_t pi=0;pi<pairs.size();++pi){auto&p=pairs[pi];if(pi)out<<',';out<<"{\"panelIDs\":["<<p.a<<','<<p.b<<"],\"panelNames\":[\""<<names[p.a]<<"\",\""<<names[p.b]<<"\"],\"minimumVFDistanceMeters\":"<<std::sqrt(p.vf)<<",\"minimumEEDistanceMeters\":"<<std::sqrt(p.ee)<<",\"nearVF\":"<<p.vfNear<<",\"nearEE\":"<<p.eeNear<<",\"exactZeroVF\":"<<p.vfZero<<",\"exactZeroEE\":"<<p.eeZero<<",\"actualIndexAdjacencySkipped\":"<<p.adjSkip<<",\"bvhNodeVisits\":"<<p.visits<<",\"minimumVFWitness\":";feature(out,p.fv);out<<",\"minimumEEWitness\":";feature(out,p.fe);out<<",\"nearFeatures\":[";for(size_t j=0;j<p.near.size();++j){if(j)out<<',';feature(out,p.near[j]);}out<<"]}";}
 double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();out<<"],\"seconds\":"<<seconds<<"}";std::cerr<<name<<" minVF="<<std::sqrt(minimumVF)<<" minEE="<<std::sqrt(minimumEE)<<" near="<<totalNear<<" zero="<<vfZero+eeZero<<" seconds="<<seconds<<'\n';
 }
 out<<"]}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
