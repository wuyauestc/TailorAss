#include <ipc/collision_mesh.hpp>
#include <ipc/collisions/normal/normal_collisions.hpp>
#include <ipc/potentials/barrier_potential.hpp>
#include <ipc/candidates/candidates.hpp>
#include <algorithm>
#include <tbb/global_control.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <cmath>
namespace {
template<class D> void vec(std::ostream&o,const Eigen::MatrixBase<D>&v){o<<'[';for(Eigen::Index i=0;i<v.size();++i){if(i)o<<',';o<<v.derived().coeff(i);}o<<']';}
void sparse(std::ostream&o,const Eigen::SparseMatrix<double>&H){o<<'[';bool first=true;for(int k=0;k<H.outerSize();++k)for(Eigen::SparseMatrix<double>::InnerIterator it(H,k);it;++it){if(it.value()==0)continue;if(!first)o<<',';first=false;o<<'['<<it.row()<<','<<it.col()<<','<<it.value()<<']';}o<<']';}
}
int main(int argc,char**argv){try{
 const bool canonical=argc==4 && std::string(argv[3])=="--canonical-candidates"; if(argc!=3&&!canonical)throw std::runtime_error("usage reference input.txt output.json");
 tbb::global_control thread_limit(tbb::global_control::max_allowed_parallelism,1);
 std::ifstream in(argv[1]);std::ofstream out(argv[2]);if(!in||!out)throw std::runtime_error("io");out<<std::setprecision(17);
 std::string magic;size_t count;in>>magic>>count;if(magic!="IPCCREF1"||count>100)throw std::runtime_error("header");
 out<<"{\"canonicalCandidateOrder\":"<<(canonical?"true":"false")<<",\"reference\":\"ipc-toolkit v1.6.1 full NormalCollisions builder; XOR cloth/body filter; full derivatives subsequently restricted to cloth prefix\",\"eigen\":\"3.4.0 EIGEN_MPL2_ONLY\",\"layout\":\"RowMajor\",\"use_area_weighting\":true,\"improved_max_approximator\":true,\"physical_barrier\":true,\"shape_derivatives\":false,\"cases\":[";
 for(size_t ci=0;ci<count;++ci){std::string name;int nc,n,ne,nf;double dmin,h,kappa;in>>name>>nc>>n>>ne>>nf>>dmin>>h>>kappa;if(!in||n<1||n>20000||nc<1||nc>n||ne<0||nf<0)throw std::runtime_error("case header");
 Eigen::MatrixXd rest(n,3),x(n,3);Eigen::MatrixXi edges(ne,2),faces(nf,3);
 for(int i=0;i<n;++i)for(int j=0;j<3;++j)in>>rest(i,j);for(int i=0;i<n;++i)for(int j=0;j<3;++j)in>>x(i,j);for(int i=0;i<ne;++i)for(int j=0;j<2;++j)in>>edges(i,j);for(int i=0;i<nf;++i)for(int j=0;j<3;++j)in>>faces(i,j);if(!in)throw std::runtime_error("case data");
 ipc::CollisionMesh mesh(rest,edges,faces);mesh.can_collide=ipc::CollisionFilter([nc](size_t i,size_t j){return (i<size_t(nc))!=(j<size_t(nc));}); ipc::Candidates diagnostic_candidates;diagnostic_candidates.build(mesh,x,.5*(h+dmin));
 ipc::NormalCollisions col;col.set_use_area_weighting(true);col.set_collision_set_type(ipc::NormalCollisions::CollisionSetType::IMPROVED_MAX_APPROX);col.set_enable_shape_derivatives(false);if(canonical){ipc::Candidates candidates;candidates.build(mesh,x,.5*(h+dmin));for(auto&ee:candidates.ee_candidates)if(ee.edge0_id>ee.edge1_id)std::swap(ee.edge0_id,ee.edge1_id);std::sort(candidates.ee_candidates.begin(),candidates.ee_candidates.end());std::sort(candidates.fv_candidates.begin(),candidates.fv_candidates.end());col.build(candidates,mesh,x,h,dmin);}else col.build(mesh,x,h,dmin);
 ipc::BarrierPotential B(h,kappa,true);double energy=B(col,mesh,x);Eigen::VectorXd g=B.gradient(col,mesh,x);auto H=B.hessian(col,mesh,x,ipc::PSDProjectionMethod::NONE);auto P=B.hessian(col,mesh,x,ipc::PSDProjectionMethod::CLAMP);
 if(!std::isfinite(energy)||!g.allFinite())throw std::runtime_error("nonfinite result");
 if(ci)out<<',';out<<"{\"name\":\""<<name<<"\",\"n_cloth\":"<<nc<<",\"n_vertices\":"<<n<<",\"fixedBodyClothPrefix\":true,\"n_body\":"<<(n-nc)<<",\"candidateCounts\":{\"vv\":"<<diagnostic_candidates.vv_candidates.size()<<",\"ev\":"<<diagnostic_candidates.ev_candidates.size()<<",\"ee\":"<<diagnostic_candidates.ee_candidates.size()<<",\"fv\":"<<diagnostic_candidates.fv_candidates.size()<<"},\"energy\":"<<energy<<",\"gradient\":";vec(out,g);out<<",\"hessian\":";sparse(out,H);out<<",\"hessian_psd\":";sparse(out,P);out<<",\"vertex_areas\":";vec(out,mesh.vertex_areas());out<<",\"edge_areas\":";vec(out,mesh.edge_areas());out<<",\"stencils\":[";
 for(size_t i=0;i<col.size();++i){const auto&c=col[i];auto ids=c.vertex_ids(mesh.edges(),mesh.faces());int kind=col.is_vertex_vertex(i)?0:(col.is_edge_vertex(i)?1:(col.is_edge_edge(i)?2:3));auto positions=c.dof(x,mesh.edges(),mesh.faces());if(i)out<<',';out<<"{\"kind\":"<<kind<<",\"ids\":[";for(int j=0;j<c.num_vertices();++j){if(j)out<<',';out<<ids[j];}out<<"],\"cloth_vertex_flags\":[";for(int j=0;j<c.num_vertices();++j){if(j)out<<',';out<<(ids[j]<nc?"true":"false");}out<<"],\"distance_squared\":"<<c.compute_distance(positions)<<",\"mollifier\":"<<c.mollifier(positions)<<",\"weight\":"<<c.weight<<",\"dmin\":"<<c.dmin<<",\"dtype\":"<<(kind==2?int(c.as<ipc::EdgeEdgeNormalCollision>().dtype):-1)<<",\"eps_x\":"<<(kind==2?c.as<ipc::EdgeEdgeNormalCollision>().eps_x:0)<<",\"energy\":"<<B(c,positions)<<",\"gradient\":";vec(out,B.gradient(c,positions));out<<",\"hessian\":";auto local=B.hessian(c,positions);out<<'[';for(int a=0;a<local.rows();++a){if(a)out<<',';out<<'[';for(int b=0;b<local.cols();++b){if(b)out<<',';out<<local(a,b);}out<<']';}out<<"]}";}
 out<<"]}";std::cerr<<name<<" "<<col.size()<<" stencils E="<<energy<<'\n';
 }
 out<<"]}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
