// Original local preprocessing utility; no MakeHuman application code used.
// Input is the derived, CC0 anatomical triangle mesh from build-standard-body.py.
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>
#include <string>
#include <vector>
struct V {double x,y,z;V operator+(V b)const{return{x+b.x,y+b.y,z+b.z};}V operator-(V b)const{return{x-b.x,y-b.y,z-b.z};}V operator*(double s)const{return{x*s,y*s,z*s};}double dot(V b)const{return x*b.x+y*b.y+z*b.z;}double axis(int a)const{return a==0?x:a==1?y:z;}};
struct Tri{V a,b,c,lo,hi,center;};
double pointTriangle2(V p,const Tri&t){V ab=t.b-t.a,ac=t.c-t.a,ap=p-t.a;double d1=ab.dot(ap),d2=ac.dot(ap);if(d1<=0&&d2<=0)return ap.dot(ap);V bp=p-t.b;double d3=ab.dot(bp),d4=ac.dot(bp);if(d3>=0&&d4<=d3)return bp.dot(bp);double vc=d1*d4-d3*d2;if(vc<=0&&d1>=0&&d3<=0){V q=t.a+ab*(d1/(d1-d3));return(p-q).dot(p-q);}V cp=p-t.c;double d5=ab.dot(cp),d6=ac.dot(cp);if(d6>=0&&d5<=d6)return cp.dot(cp);double vb=d5*d2-d1*d6;if(vb<=0&&d2>=0&&d6<=0){V q=t.a+ac*(d2/(d2-d6));return(p-q).dot(p-q);}double va=d3*d6-d5*d4;if(va<=0&&(d4-d3)>=0&&(d5-d6)>=0){V q=t.b+(t.c-t.b)*((d4-d3)/((d4-d3)+(d5-d6)));return(p-q).dot(p-q);}double denom=1/(va+vb+vc);V q=t.a+ab*(vb*denom)+ac*(vc*denom);return(p-q).dot(p-q);}
struct Node{V lo,hi;int start,count,left=-1,right=-1;};
struct BVH{std::vector<Tri> t;std::vector<int>ids;std::vector<Node>nodes;int build(int start,int count){V lo{1e9,1e9,1e9},hi{-1e9,-1e9,-1e9};for(int i=start;i<start+count;i++){auto&q=t[ids[i]];lo={std::min(lo.x,q.lo.x),std::min(lo.y,q.lo.y),std::min(lo.z,q.lo.z)};hi={std::max(hi.x,q.hi.x),std::max(hi.y,q.hi.y),std::max(hi.z,q.hi.z)};}int n=nodes.size();nodes.push_back({lo,hi,start,count});if(count>8){V range=hi-lo;int axis=range.x>range.y?(range.x>range.z?0:2):(range.y>range.z?1:2);int mid=start+count/2;std::nth_element(ids.begin()+start,ids.begin()+mid,ids.begin()+start+count,[&](int a,int b){return t[a].center.axis(axis)<t[b].center.axis(axis);});int l=build(start,count/2),r=build(mid,count-count/2);nodes[n].left=l;nodes[n].right=r;}return n;}
double box2(V p,int node)const{auto&n=nodes[node];double x=std::max({n.lo.x-p.x,0.0,p.x-n.hi.x}),y=std::max({n.lo.y-p.y,0.0,p.y-n.hi.y}),z=std::max({n.lo.z-p.z,0.0,p.z-n.hi.z});return x*x+y*y+z*z;}
void nearest(V p,int ni,double&best)const{if(box2(p,ni)>=best)return;auto&n=nodes[ni];if(n.left<0){for(int i=n.start;i<n.start+n.count;i++)best=std::min(best,pointTriangle2(p,t[ids[i]]));return;}double l=box2(p,n.left),r=box2(p,n.right);if(l<r){nearest(p,n.left,best);nearest(p,n.right,best);}else{nearest(p,n.right,best);nearest(p,n.left,best);}}
};
int main(int argc,char**argv){if(argc!=3)return 2;std::ifstream in(argv[1]);if(!in)return 3;std::vector<V>v;BVH bvh;std::string line;while(std::getline(in,line)){std::istringstream s(line);std::string tag;s>>tag;if(tag=="v"){V p;s>>p.x>>p.y>>p.z;v.push_back(p);}else if(tag=="f"){int a,b,c;s>>a>>b>>c;V x=v[a-1],y=v[b-1],z=v[c-1];bvh.t.push_back({x,y,z,{std::min({x.x,y.x,z.x}),std::min({x.y,y.y,z.y}),std::min({x.z,y.z,z.z})},{std::max({x.x,y.x,z.x}),std::max({x.y,y.y,z.y}),std::max({x.z,y.z,z.z})},(x+y+z)*(1.0/3)});}}bvh.ids.resize(bvh.t.size());std::iota(bvh.ids.begin(),bvh.ids.end(),0);bvh.build(0,bvh.ids.size());
// Extend only +Y: the original lower-body samples keep identical coordinates.
const V origin{-.6337,-1.1137,-.3037};const double spacing=.01;const int nx=128,ny=181,nz=65;std::vector<float>out(nx*ny*nz);int oddRows=0;
for(int z=0;z<nz;z++){for(int y=0;y<ny;y++){double yy=origin.y+y*spacing,zz=origin.z+z*spacing;std::vector<double>crossings;for(auto&t:bvh.t){if(yy<t.lo.y||yy>t.hi.y||zz<t.lo.z||zz>t.hi.z)continue;double den=(t.b.y-t.c.y)*(t.a.z-t.c.z)+(t.c.z-t.b.z)*(t.a.y-t.c.y);if(std::abs(den)<1e-14)continue;double a=((t.b.y-t.c.y)*(zz-t.c.z)+(t.c.z-t.b.z)*(yy-t.c.y))/den,b=((t.c.y-t.a.y)*(zz-t.c.z)+(t.a.z-t.c.z)*(yy-t.c.y))/den,c=1-a-b;if(std::min({a,b,c})>=-1e-10)crossings.push_back(a*t.a.x+b*t.b.x+c*t.c.x);}std::sort(crossings.begin(),crossings.end());crossings.erase(std::unique(crossings.begin(),crossings.end(),[](double a,double b){return std::abs(a-b)<1e-7;}),crossings.end());if(crossings.size()%2)oddRows++;
for(int x=0;x<nx;x++){V p{origin.x+x*spacing,yy,zz};double best=1e9;bvh.nearest(p,0,best);int count=std::upper_bound(crossings.begin(),crossings.end(),p.x)-crossings.begin();out[(z*ny+y)*nx+x]=(float)(std::sqrt(best)*(count%2?-1:1));}}
if(z%10==0)std::cerr<<"slice "<<z<<"/"<<nz<<"\n";}
std::ofstream f(argv[2],std::ios::binary);f.write((char*)out.data(),out.size()*sizeof(float));std::cerr<<"Wrote "<<out.size()<<" floats ("<<out.size()*4<<" bytes), odd ray rows="<<oddRows<<"\n";return oddRows?4:0;}
