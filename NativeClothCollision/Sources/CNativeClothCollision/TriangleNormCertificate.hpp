#pragma once
#include <array>
#include <algorithm>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <limits>

// Our private input-domain certificate, not an upstream CCD predicate. Every
// interval operation encloses exact real arithmetic on the binary64 inputs.
// A failed/budget-limited certificate never authorizes a path or a no-hit.
namespace ncc_triangle_norm {
struct Interval { double lo, hi; };
using Vector = std::array<Interval,3>;
using Coefficients = std::array<Interval,5>;
enum class Reason { certified, invalid, unsupportedIEEE, arithmetic, nearEndpoint, depthBudget, nodeBudget };
struct NoObserver {
    void start(Interval,Interval,const Coefficients&) const {}
    void accepted(std::uint32_t,int,const Coefficients&) const {}
    void finish(Reason,int,int) const {}
};
inline double down(double x) { return std::nextafter(x,-std::numeric_limits<double>::infinity()); }
inline double up(double x) { return std::nextafter(x,std::numeric_limits<double>::infinity()); }
inline Interval point(double x) { return {x,x}; }
inline Interval add(Interval a,Interval b) { return {down(a.lo+b.lo),up(a.hi+b.hi)}; }
inline Interval sub(Interval a,Interval b) { return {down(a.lo-b.hi),up(a.hi-b.lo)}; }
inline Interval mul(Interval a,Interval b) {
    const double p[]={a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi};
    return {down(*std::min_element(p,p+4)),up(*std::max_element(p,p+4))};
}
inline Interval divide(Interval a,double positive) { return {down(a.lo/positive),up(a.hi/positive)}; }
inline Interval square(Interval a) {
    const double x=a.lo*a.lo,y=a.hi*a.hi;
    return {a.lo<=0&&a.hi>=0 ? 0:down(std::min(x,y)),up(std::max(x,y))};
}
inline bool finite(Interval a) { return std::isfinite(a.lo)&&std::isfinite(a.hi)&&a.lo<=a.hi; }
inline Vector difference(const double*a,const double*b) {
    return {sub(point(a[0]),point(b[0])),sub(point(a[1]),point(b[1])),sub(point(a[2]),point(b[2]))};
}
inline Vector cross(const Vector&a,const Vector&b) {
    return {sub(mul(a[1],b[2]),mul(a[2],b[1])),sub(mul(a[2],b[0]),mul(a[0],b[2])),sub(mul(a[0],b[1]),mul(a[1],b[0]))};
}
inline Interval dot(const Vector&a,const Vector&b) { return add(add(mul(a[0],b[0]),mul(a[1],b[1])),mul(a[2],b[2])); }
inline Interval normSquared(const Vector&a) { return add(add(square(a[0]),square(a[1])),square(a[2])); }
inline bool ieeeReady() {
#ifdef __FAST_MATH__
    return false;
#endif
    if(std::fegetround()!=FE_TONEAREST)return false;
    // Refuse FTZ/DAZ rather than assuming gradual underflow in the interval proof.
    volatile double tiny=std::numeric_limits<double>::denorm_min();
    volatile double sum=tiny+tiny;
    return sum==std::nextafter(double(tiny),std::numeric_limits<double>::infinity());
}
// Private finite budgets, independently reducible by the audit harness. They
// cannot enlarge the existing native CCD iteration or working-memory budgets.
constexpr int maximumDepth=12,maximumNodes=128;
template<class Observer>
bool certify(const double*a,const double*b,double time,double originalEpsilon,
             int depthLimit,int nodeLimit,Observer&observer) {
    int visited=0,deepest=0;
    auto finish=[&](Reason reason,bool value) {observer.finish(reason,visited,deepest);return value;};
    if(!a||!b||!std::isfinite(time)||time<=0||time>1||!std::isfinite(originalEpsilon)||originalEpsilon<=0||
       depthLimit<0||depthLimit>maximumDepth||nodeLimit<1||nodeLimit>maximumNodes)return finish(Reason::invalid,false);
    if(!ieeeReady())return finish(Reason::unsupportedIEEE,false);
    for(int i=0;i<12;++i)if(!std::isfinite(a[i])||!std::isfinite(b[i])||std::abs(a[i])>1e6||std::abs(b[i])>1e6)return finish(Reason::invalid,false);
    const Vector u0=difference(a+6,a+3),v0=difference(a+9,a+3);
    const Vector uFull=difference(b+6,b+3),vFull=difference(b+9,b+3);
    Vector u1=uFull,v1=vFull;
    if(time!=1)for(int i=0;i<3;++i) {
        // Normalized s in [0,1] covers the actual original t in [0,time].
        u1[i]=add(u0[i],mul(point(time),sub(uFull[i],u0[i])));
        v1[i]=add(v0[i],mul(point(time),sub(vFull[i],v0[i])));
    }
    const Vector n0=cross(u0,v0),n2=cross(u1,v1),first=cross(u0,v1),second=cross(u1,v0);
    Vector n1;for(int i=0;i<3;++i)n1[i]=divide(add(first[i],second[i]),2);
    const Interval epsilon=point(originalEpsilon),epsilonSquared=square(epsilon);
    const Coefficients root={normSquared(n0),dot(n0,n1),divide(add(dot(n0,n2),mul(point(2),normSquared(n1))),3),dot(n1,n2),normSquared(n2)};
    observer.start(epsilon,epsilonSquared,root);
    if(!finite(epsilonSquared))return finish(Reason::arithmetic,false);
    struct Segment {Coefficients q;int depth;std::uint32_t path;};
    // Depth-first binary traversal needs at most depth+1 pending segments.
    std::array<Segment,maximumDepth+2> stack{};int count=1;stack[0]={root,0,0};
    while(count) {
        if(visited>=nodeLimit)return finish(Reason::nodeBudget,false);
        const Segment leaf=stack[--count];++visited;deepest=std::max(deepest,leaf.depth);
        bool positive=true;
        for(Interval q:leaf.q) {if(!finite(q))return finish(Reason::arithmetic,false);positive=positive&&q.lo>epsilonSquared.hi;}
        if(positive) {observer.accepted(leaf.path,leaf.depth,leaf.q);continue;}
        if(leaf.q[0].hi<=epsilonSquared.lo||leaf.q[4].hi<=epsilonSquared.lo)return finish(Reason::nearEndpoint,false);
        if(leaf.depth>=depthLimit)return finish(Reason::depthBudget,false);
        Coefficients row=leaf.q,left{},right{};left[0]=row[0];right[4]=row[4];
        for(int r=1;r<=4;++r) {
            for(int i=0;i<=4-r;++i)row[i]=divide(add(row[i],row[i+1]),2);
            left[r]=row[0];right[4-r]=row[4-r];
        }
        if(count+2>int(stack.size()))return finish(Reason::nodeBudget,false);
        stack[count++]={right,leaf.depth+1,std::uint32_t((leaf.path<<1)|1)};
        stack[count++]={left,leaf.depth+1,std::uint32_t(leaf.path<<1)};
    }
    return finish(Reason::certified,true);
}
inline bool certified(const double*a,const double*b,double time,double originalEpsilon) {
    NoObserver observer;
    return certify(a,b,time,originalEpsilon,maximumDepth,maximumNodes,observer);
}
}
