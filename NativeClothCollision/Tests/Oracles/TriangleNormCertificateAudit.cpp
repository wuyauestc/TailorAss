#include <array>
#include <algorithm>
#include <cmath>
#include <cfenv>
#include <chrono>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
#include "../../Sources/CNativeClothCollision/TriangleNormCertificate.hpp"
static_assert(std::numeric_limits<double>::is_iec559 && sizeof(double)==8,"binary64 required");
using V=std::array<double,3>;
using I=ncc_triangle_norm::Interval;
using Coeff=ncc_triangle_norm::Coefficients;
struct Leaf {std::string path;Coeff coeff;};
struct Result {bool certified=false;std::string reason;int visited=0,maximumDepth=0;I epsilon{},epsilonSquared{};Coeff root{};std::vector<Leaf> leaves;};
static Result certify(const std::array<V,3>&a,const std::array<V,3>&b,int depth=12,int budget=128,double maximumTime=1){
    Result result;
    struct Observer {
        Result&result;
        void start(I e,I e2,const Coeff&q){result.epsilon=e;result.epsilonSquared=e2;result.root=q;}
        void accepted(std::uint32_t bits,int depth,const Coeff&q){std::string path;for(int i=depth-1;i>=0;--i)path+=((bits>>i)&1)?'R':'L';result.leaves.push_back({path,q});}
        void finish(ncc_triangle_norm::Reason r,int visited,int depth){
            static const char*names[]={"positiveNormSquaredOnCompleteInterval","invalidArguments","unsupportedIEEEEnvironment","nonfiniteArithmetic","provedNearDegenerateEndpoint","depthBudget","segmentBudget"};
            result.reason=names[int(r)];result.visited=visited;result.maximumDepth=depth;
        }
    } observer{result};
    std::array<double,12> first{},second{};
    for(int i=0;i<3;++i)for(int j=0;j<3;++j){first[3+3*i+j]=a[i][j];second[3+3*i+j]=b[i][j];}
    V u{},v{};double su=0,sv=0;
    for(int j=0;j<3;++j){u[j]=a[1][j]-a[0][j];v[j]=a[2][j]-a[0][j];su+=u[j]*u[j];sv+=v[j]*v[j];}
    const double eps=std::max(1e-24,std::max(su,sv)*1e-12);
    result.certified=ncc_triangle_norm::certify(first.data(),second.data(),maximumTime,eps,depth,budget,observer);
    return result;
}
static V subd(V a,V b){return {a[0]-b[0],a[1]-b[1],a[2]-b[2]};}
static V crossd(V a,V b){return {a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};}
static double dotd(V a,V b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
static bool originalCertificate(const std::array<V,3>&a,const std::array<V,3>&b){
    V u=subd(a[1],a[0]),v=subd(a[2],a[0]),du=subd(subd(b[1],b[0]),u),dv=subd(subd(b[2],b[0]),v),n=crossd(u,v);
    const double area=std::sqrt(dotd(n,n)),eps=std::max(1e-24,std::max(dotd(u,u),dotd(v,v))*1e-12);
    if(!std::isfinite(area)||area<=eps)return false;V normal=n;for(double&x:normal)x/=area;
    V x=crossd(du,v),y=crossd(u,dv);for(int i=0;i<3;++i)x[i]+=y[i];
    const double c1=dotd(x,normal),c2=dotd(crossd(du,dv),normal);
    return area>eps&&area+.5*c1>eps&&area+c1+c2>eps;
}
struct Case{std::string name;std::array<V,3>a,b;bool expected;int depth=12,budget=128;double maximumTime=1;};
static void intervalJSON(I a){std::cout<<'['<<a.lo<<','<<a.hi<<']';}
static void coeffJSON(const Coeff&q){std::cout<<'[';for(int i=0;i<5;++i){if(i)std::cout<<',';intervalJSON(q[i]);}std::cout<<']';}
static void triangleJSON(const std::array<V,3>&a){std::cout<<'[';for(int i=0;i<3;++i){if(i)std::cout<<',';std::cout<<'['<<a[i][0]<<','<<a[i][1]<<','<<a[i][2]<<']';}std::cout<<']';}
int main(int argc,char**argv){
    if(argc<2||argc>3)return 2;
    const std::array<V,3> a={V{0,0,0},V{1,0,0},V{0,1,0}};
    std::vector<Case> cases;
    for(double angle:{0.,30.,89.,90.,117.,179.}){
        const double t=angle*std::acos(-1.)/180;auto b=a;b[2]={0,std::cos(t),std::sin(t)};
        cases.push_back({"axisRotation"+std::to_string(int(angle)),a,b,true});
    }
    auto opposite=a;opposite[2]={0,-1,0};cases.push_back({"midCollapseOneEdge",a,opposite,false});
    auto invert=a;invert[1]={-1,0,0};invert[2]={0,-1,0};cases.push_back({"midCollapseBothEdgesEndpointsAreaPositive",a,invert,false});
    auto quarter=a;quarter[1]={-3,0,0};cases.push_back({"quarterCollapse",a,quarter,false});
    auto third=a;third[1]={-2,0,0};cases.push_back({"nonDyadicCollapse",a,third,false});
    cases.push_back({"clippedBeforeCollapse",a,opposite,true,12,128,0.25});
    cases.push_back({"clippedAtCollapse",a,opposite,false,12,128,0.5});
    cases.push_back({"clippedBeyondCollapse",a,opposite,false,12,128,0.75});
    cases.push_back({"clippedJustBeforeCollapseAboveThreshold",a,opposite,true,12,128,0.49});
    auto near=a;near[2]={1,1e-13,0};cases.push_back({"staticNearDegenerate",near,near,false});
    auto above=a;above[2]={1,1.1e-12,0};cases.push_back({"staticAboveOriginalThreshold",above,above,true});
    auto turn=a;turn[2]={0,std::cos(117*std::acos(-1.)/180),std::sin(117*std::acos(-1.)/180)};
    auto hardTurn=a;hardTurn[2]={0,std::cos(179*std::acos(-1.)/180),std::sin(179*std::acos(-1.)/180)};
    cases.push_back({"requiredSubdivisionBudgetExhausted",a,hardTurn,false,12,1});
    cases.push_back({"requiredSubdivisionDepthExhausted",a,hardTurn,false,0,128});
    for(double scale:{1e-6,1e-3,1.,1e3}){
        auto x=a,y=turn;for(int i=0;i<3;++i)for(int j=0;j<3;++j){x[i][j]=x[i][j]*scale+(j+1)*scale*.3;y[i][j]=y[i][j]*scale+(j+1)*scale*.3;}
        cases.push_back({"scaledTranslatedRotation"+std::to_string(scale),x,y,true});
    }
    std::ifstream f(argv[1]);std::array<V,3> actualA,actualB;
    for(auto&v:actualA)for(double&x:v)f>>x;for(auto&v:actualB)for(double&x:v)f>>x;
    if(!f)return 3;cases.push_back({"actualClothFrame469to470",actualA,actualB,true});
    if(argc==3){
        const int count=std::stoi(argv[2]);volatile int total=0;
        for(const auto&item:std::vector<Case>{{"actual",actualA,actualB,true},{"static",a,a,true},{"collapse",a,invert,false}}){
            const auto start=std::chrono::steady_clock::now();
            for(int i=0;i<count;++i){const auto r=certify(item.a,item.b);total+=r.visited;}
            const double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
            std::cerr<<"BENCH "<<item.name<<" count="<<count<<" seconds="<<seconds<<" microsecondsPerCertificate="<<seconds/count*1e6<<"\n";
        }
        if(total<0)return 9;
    }
    std::cout<<std::setprecision(17)<<"{\"scope\":\"Isolated original-threshold interval norm-squared certificate, not a changed CCD or cloth solver\",\"cases\":[";
    int failures=0;
    for(std::size_t i=0;i<cases.size();++i){const auto&c=cases[i];const Result r=certify(c.a,c.b,c.depth,c.budget,c.maximumTime);if(r.certified!=c.expected)++failures;
        if(i)std::cout<<',';std::cout<<"{\"id\":\""<<c.name<<"\",\"expected\":"<<(c.expected?"true":"false")<<",\"certified\":"<<(r.certified?"true":"false")<<",\"originalCertificate\":"<<(originalCertificate(c.a,c.b)?"true":"false")<<",\"reason\":\""<<r.reason<<"\",\"visitedSegments\":"<<r.visited<<",\"maximumDepth\":"<<r.maximumDepth<<",\"maximumTime\":"<<c.maximumTime<<",\"start\":";triangleJSON(c.a);std::cout<<",\"end\":";triangleJSON(c.b);std::cout<<",\"epsilon\":";intervalJSON(r.epsilon);std::cout<<",\"epsilonSquared\":";intervalJSON(r.epsilonSquared);std::cout<<",\"rootBernstein\":";coeffJSON(r.root);std::cout<<",\"acceptedLeaves\":[";
        for(std::size_t j=0;j<r.leaves.size();++j){if(j)std::cout<<',';std::cout<<"{\"path\":\""<<r.leaves[j].path<<"\",\"coefficients\":";coeffJSON(r.leaves[j].coeff);std::cout<<'}';}std::cout<<"]}";
    }
    // Explicit unsupported rounding-mode refusal (production already requires nearest).
    std::fesetround(FE_DOWNWARD);const auto wrong=certify(a,a);std::fesetround(FE_TONEAREST);
    if(wrong.certified||wrong.reason!="unsupportedIEEEEnvironment")++failures;
    std::cout<<"],\"unsupportedRoundingRefused\":"<<(!wrong.certified?"true":"false")<<",\"failures\":"<<failures<<"}\n";
    return failures?1:0;
}
