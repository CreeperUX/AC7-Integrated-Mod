// Levelling must resume after the bank is moved away from wings-level once a levelling has completed (keyboard roll
// takeover). F-18F flight (v13.6): after a keyboard roll to 94 deg the quintic levelling stayed "done" and held the
// bank for 15 s. Exact AC8 plant (fe_model) with extracted aircraft parameters; private test (not in the public tree).
#include "src/fe_control.h"
#include "src/fe_aircraft_table.h"
#include <cassert>
#include <cstdio>
#include <cmath>
static flight::V rot(flight::V v,flight::V omega){
 double n=std::sqrt(double(flight::dot(omega,omega)));if(n<1e-12)return v;
 auto axis=omega*float(1/n);double a=n*flight::rad,c=std::cos(a),s=std::sin(a);
 return v*float(c)+flight::cross(axis,v)*float(s)+axis*float(flight::dot(axis,v)*(1-c));
}
struct Result{double relevel=-1,max_bank_after=0;};
// Nose on a still target, banked bank0; a keyboard roll of disturb_bank deg over 0.6 s starts at disturb_t (the
// controller's roll output keeps running but the extra rotation is not commanded by it).
static Result run(const char* code,double kmh,double bank0,double disturb_t,double disturb_bank,fe_control::Tuning TU={}){
 const fe::Params* FP=fe_table::find_code(code);assert(FP&&FP->valid);
 const double speed=kmh/3.6,dt=1/60.;auto body=flight::basis(0,0,float(bank0));const auto target=body.f;
 double S[3]{},R[3]{};fe_control::Controller fec;aim_motion::Estimator est;Result out;double t=0;
 while(t<14){
  fe_control::Geometry g;g.goal={flight::dot(body.f,target),flight::dot(body.r,target),flight::dot(body.u,target)};
  g.bank_r=body.r.z;g.bank_u=body.u.z;g.up_f=body.f.z;
  est.update(t,target);g.aim_speed=float(est.speed);g.aim_still=float(est.still);g.aim_up=flight::dot(est.vel,body.u);g.aim_right=flight::dot(est.vel,body.r);
  g.aim_path=float(est.path_speed);g.aim_moving=float(est.moving);g.aim_quiet=float(est.quiet);
  const auto o=fec.step(*FP,S,R,speed,dt,g,fe_control::Mode::Stick,TU);assert(o.valid);
  const auto cp=fe::caps(*FP,speed);
  S[0]=fe::input_axis(*FP,0,S[0],o.stick[0],dt);S[2]=fe::input_axis(*FP,2,S[2],o.stick[2],dt);S[1]=std::clamp(o.S[1],-1.0,1.0);
  for(int a=0;a<3;++a)R[a]=fe::rate_axis(*FP,a,R[a],S[a],cp.cap[a],dt);
  const double ap=fe::applied_pitch(*FP,R[0],fe::bank_assist(cp,body.u.z));
  const float rp=float(ap/flight::rad),rr=float(R[2]/flight::rad),ry=float(R[1]/flight::rad);
  auto w=body.f*float(-rr*dt)+body.r*float(-rp*dt)+body.u*float(ry*dt);
  if(t>=disturb_t&&t<disturb_t+.6)w=w+body.f*float(-disturb_bank/.6*dt);
  body.f=flight::unit(rot(body.f,w));body.r=flight::unit(rot(body.r,w));body.u=flight::unit(flight::cross(body.f,body.r));body.r=flight::cross(body.u,body.f);
  t+=dt;
  const double bank=std::atan2(-body.r.z,body.u.z)/flight::rad;
  if(t>disturb_t+.6){out.max_bank_after=std::max(out.max_bank_after,std::abs(bank));if(out.relevel<0&&std::abs(bank)<3)out.relevel=t-disturb_t-.6;}
 }
 return out;
}
int main(){
 // 1. keyboard roll to ~94 deg after the levelling has completed: levels again (~0.8 s), F-18F and Su-57
 for(auto c:{std::pair<const char*,double>{"PP0024_f18f",700},{"PP0024_f18f",400},{"PP0021_su57",430},{"PP0008_j39e",600}}){
  auto r=run(c.first,c.second,60,5,94);
  std::printf("  %s %4.0f km/h: re-levelled %.2f s after the keyboard roll\n",c.first,c.second,r.relevel);
  assert(r.relevel>0&&r.relevel<2.5);
 }
 // 2. keyboard roll while the levelling is still running
 {auto r=run("PP0024_f18f",700,90,.5,60);assert(r.relevel>0&&r.relevel<3);}
 // 3. regression guard: without re-arming the completed levelling holds the moved bank (the v13.6 defect)
 {fe_control::Tuning k;k.level_rearm=1e9;auto r=run("PP0024_f18f",700,60,5,94,k);assert(r.relevel<0&&r.max_bank_after>60);}
 std::puts("PASS completed levelling re-arms after a keyboard roll (F-18F/Su-57/JAS39E), mid-levelling takeover recovers, defect reproduced without re-arm");
}
