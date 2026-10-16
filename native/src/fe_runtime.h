#pragma once
// Runtime glue for WAR (control mode 3) on ACE COMBAT 7: exact flight-engine state read from the player's flight
// engine inside the hooked input stage 0x1CE24F0(core, dt) (ac7/docs/AC7-FlightEngine-逆向.md). Same controller and
// hand-off as the AC8 build; only the layout differs. Every read is guarded and validated, and any failure falls
// back to WAR v11.1 (degraded mode).
#include "fe_control.h"
#include "manual_takeover.h"
#include <share.h>

namespace fe_runtime {

// pawn+0x1410 -> flight-engine object FE; core = FE+0xB0. Attitude rows (body X, Y, Z in FE world) at FE+0x70/0x80/0x90.
constexpr uintptr_t OFF_FE_PTR=0x1410,CORE=0xB0,FE_ROWS=0x70;
constexpr size_t C_SPEED=0x20,C_RAW_PITCH=0x30,C_RAW_ROLL=0x34,C_RAW_YAW=0x38,C_R=0xF0,C_S=0x170,C_CAP=0x2E0,C_FLAGS=0x1A4,C_NOVICE=0xBD3;
constexpr size_t P_BYTES=0x700;   // core-relative parameter span read by fe::from_memory_ac7
// Mode bits of core+0x1A4 that leave the modelled law: 0x80 high-G turn (brake + pull, pitch rate divided by a
// state-dependent factor), 0x200 / 0x400 / 0x800 / 0x1000 drift / PSM / special branches.
constexpr uint32_t SPECIAL_FLAGS=0x80|0x200|0x400|0x800|0x1000;

struct Quat {double x=0,y=0,z=0,w=1;};
inline flight::V rot(const Quat& q,flight::V v){   // q * v * q^-1
 const double ux=q.x,uy=q.y,uz=q.z,vx=v.x,vy=v.y,vz=v.z;
 const double tx=2*(uy*vz-uz*vy),ty=2*(uz*vx-ux*vz),tz=2*(ux*vy-uy*vx);
 return {float(vx+q.w*tx+(uy*tz-uz*ty)),float(vy+q.w*ty+(uz*tx-ux*tz)),float(vz+q.w*tz+(ux*ty-uy*tx))};
}
inline Quat conj(const Quat& q){return {-q.x,-q.y,-q.z,q.w};}
// Body->world rotation whose columns are the body axes (the FE matrix rows).
inline Quat quat_from_axes(const double X[3],const double Y[3],const double Z[3]){
 const double m00=X[0],m10=X[1],m20=X[2],m01=Y[0],m11=Y[1],m21=Y[2],m02=Z[0],m12=Z[1],m22=Z[2];
 Quat q;const double tr=m00+m11+m22;
 if(tr>0){const double s=std::sqrt(tr+1)*2;q.w=.25*s;q.x=(m21-m12)/s;q.y=(m02-m20)/s;q.z=(m10-m01)/s;}
 else if(m00>m11&&m00>m22){const double s=std::sqrt(1+m00-m11-m22)*2;q.w=(m21-m12)/s;q.x=.25*s;q.y=(m01+m10)/s;q.z=(m02+m20)/s;}
 else if(m11>m22){const double s=std::sqrt(1+m11-m00-m22)*2;q.w=(m02-m20)/s;q.x=(m01+m10)/s;q.y=.25*s;q.z=(m12+m21)/s;}
 else{const double s=std::sqrt(1+m22-m00-m11)*2;q.w=(m10-m01)/s;q.x=(m02+m20)/s;q.y=(m12+m21)/s;q.z=.25*s;}
 return q;
}

// Frame correspondence (identical to AC8, re-verified on AC7 attitude samples): FE body X is the LEFT wing, Y up,
// Z forward. Mod/UE body axes are (f, r, u) with r the right wing, so FE (X,Y,Z) = (-r, u, f). The controller works
// in the mod frame (+roll = right wing down, +yaw = nose right); FE roll and yaw command states and rates are mirrored.
inline flight::V fe_from_mod(flight::V m){return {-m.y,m.z,m.x};}   // (f,r,u) -> (X,Y,Z)
inline flight::V mod_from_fe(flight::V v){return {v.z,-v.x,v.y};}   // (X,Y,Z) -> (f,r,u)
constexpr double MIRROR[3]={1,-1,-1};                                 // pitch, yaw, roll: FE <-> mod

inline uintptr_t core_of(uintptr_t pawn){
 __try{
  if(pawn<65536)return 0;
  const uintptr_t fe=*reinterpret_cast<const uintptr_t*>(pawn+OFF_FE_PTR);
  if(fe<65536||(fe&7))return 0;
  return fe+CORE;
 }__except(EXCEPTION_EXECUTE_HANDLER){return 0;}
}

// Raw reads (POD only, SEH-safe). S/R in FE axis order (X pitch, Y yaw, Z roll).
struct Raw {double S[3];double R[3];double cap[3];float speed;double X[3],Y[3],Z[3];uint32_t flags;unsigned char novice;};
inline bool read_raw(uintptr_t core,Raw& out){
 __try{
  float s[3],r[3],cp[3],m[12];
  std::memcpy(cp,reinterpret_cast<const void*>(core+C_CAP),12);
  std::memcpy(s,reinterpret_cast<const void*>(core+C_S),12);
  std::memcpy(r,reinterpret_cast<const void*>(core+C_R),12);
  std::memcpy(&out.speed,reinterpret_cast<const void*>(core+C_SPEED),4);
  std::memcpy(m,reinterpret_cast<const void*>(core-CORE+FE_ROWS),48);
  std::memcpy(&out.flags,reinterpret_cast<const void*>(core+C_FLAGS),4);
  out.novice=*reinterpret_cast<const unsigned char*>(core+C_NOVICE);
  for(int a=0;a<3;++a){out.S[a]=s[a];out.R[a]=r[a];out.cap[a]=cp[a];out.X[a]=m[a];out.Y[a]=m[4+a];out.Z[a]=m[8+a];}
 }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
 return true;
}
inline bool read_params_raw(uintptr_t core,unsigned char* buf){
 __try{std::memcpy(buf,reinterpret_cast<const void*>(core),P_BYTES);}__except(EXCEPTION_EXECUTE_HANDLER){return false;}
 return true;
}
inline bool quat_of(const Raw& r,Quat& q){
 auto n=[](const double* v){return std::sqrt(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]);};
 for(const double* v:{r.X,r.Y,r.Z}){const double l=n(v);if(!std::isfinite(l)||std::abs(l-1)>.01)return false;}
 if(std::abs(r.X[0]*r.Y[0]+r.X[1]*r.Y[1]+r.X[2]*r.Y[2])>.02||std::abs(r.Y[0]*r.Z[0]+r.Y[1]*r.Z[1]+r.Y[2]*r.Z[2])>.02)return false;
 q=quat_from_axes(r.X,r.Y,r.Z);const double l=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);
 if(!std::isfinite(l)||l<.5)return false;q.x/=l;q.y/=l;q.z/=l;q.w/=l;return true;
}
inline bool read_quat(uintptr_t pawn,Quat& q){const uintptr_t core=core_of(pawn);Raw r;return core&&read_raw(core,r)&&quat_of(r,q);}

// Lua-tick hand-off: target in body axes at the instant the UE pose was sampled, plus the
// flight-engine attitude at that same instant. The hook re-expresses the target in the current
// body frame with the attitude change since, so no world-frame mapping between UE and the
// flight engine is assumed.
struct Goal {uintptr_t pawn=0;Quat q;flight::V body{1,0,0};float ff_pitch=0,ff_yaw=0,mot_up=0,mot_right=0;uint64_t tick=0;bool valid=false;};
inline Goal goal;inline std::mutex goal_mutex;
inline std::atomic<float> calib_pitch_err{0},calib_bank_err{0};inline std::atomic<int> calib_bad{0};

// Called on the Lua tick with the UE body basis used for aiming. Also checks that the flight-engine
// attitude agrees with the UE pose (pitch and bank), which validates the axis correspondence.
inline void publish_goal(uintptr_t pawn,const flight::Basis& b,flight::V aim,float ff_pitch,float ff_yaw,uint64_t tick,float mot_up=0,float mot_right=0){
 Quat q;
 if(!pawn||!read_quat(pawn,q)){std::lock_guard<std::mutex> l(goal_mutex);goal.valid=false;return;}
 // FE body axes: X left wing, Y up, Z forward; FE world up is +Y.
 const auto fwd=rot(q,{0,0,1}),left=rot(q,{1,0,0}),up=rot(q,{0,1,0});
 const float pe=std::abs(std::asin(std::clamp(fwd.y,-1.f,1.f))-std::asin(std::clamp(b.f.z,-1.f,1.f)))/flight::rad;
 const float be=std::abs(std::remainder(std::atan2(-left.y,up.y)-std::atan2(b.r.z,b.u.z),2*3.14159265f))/flight::rad;
 calib_pitch_err=pe;calib_bank_err=std::abs(fwd.y)<.9f?be:0.f;
 if(pe>3||(std::abs(fwd.y)<.9f&&be>5))calib_bad=std::min(calib_bad.load()+1,1000);else calib_bad=std::max(calib_bad.load()-5,0);
 std::lock_guard<std::mutex> l(goal_mutex);
 goal.pawn=pawn;goal.q=q;goal.body={flight::dot(aim,b.f),flight::dot(aim,b.r),flight::dot(aim,b.u)};
 goal.ff_pitch=ff_pitch;goal.ff_yaw=ff_yaw;goal.mot_up=mot_up;goal.mot_right=mot_right;goal.tick=tick;goal.valid=true;
}
inline void invalidate(){std::lock_guard<std::mutex> l(goal_mutex);goal.valid=false;}

// Per-frame trace (bounded queue, drained by the existing logger thread).
struct Record {uint64_t t;int mode;float dt,speed;float goal[3],bank_r,bank_u,ff[2];double S[3],R[3],stick[3],Sout[3],err[3],stop[3];float angle,calib_p,calib_b,aim_speed,aim_still;};
inline std::mutex trace_mutex;inline std::array<Record,4096> trace_queue;inline size_t trace_head=0,trace_size=0;
inline std::atomic<uint64_t> trace_dropped{0};inline FILE* trace_file=nullptr;inline bool trace_failed=false;inline uint64_t trace_rows=0;
inline std::atomic<bool> trace_enabled{false};   // flight_recording=1 (AC8 2.4.3/2.5.0); off: no FE CSV is created
inline void trace_push(const Record& r){
 if(!trace_enabled.load(std::memory_order_relaxed))return;
 std::unique_lock<std::mutex> lock(trace_mutex,std::try_to_lock);
 if(!lock.owns_lock()||trace_size==trace_queue.size()){++trace_dropped;return;}
 trace_queue[(trace_head+trace_size)%trace_queue.size()]=r;++trace_size;
}
inline void trace_drain(const wchar_t* module_folder){
 if(trace_failed)return;
 std::array<Record,256> batch;size_t count=0;
 {std::unique_lock<std::mutex> lock(trace_mutex,std::try_to_lock);if(!lock.owns_lock())return;
  count=std::min(batch.size(),trace_size);
  for(size_t i=0;i<count;++i)batch[i]=trace_queue[(trace_head+i)%trace_queue.size()];
  trace_head=(trace_head+count)%trace_queue.size();trace_size-=count;}
 if(!count)return;
 if(!trace_file){
  wchar_t folder[MAX_PATH]{},path[MAX_PATH]{};swprintf_s(folder,L"%s\\..\\Logs",module_folder);CreateDirectoryW(folder,nullptr);
  for(int n=1;n<10000;++n){swprintf_s(path,L"%s\\FE-%05d.csv",folder,n);if(GetFileAttributesW(path)!=INVALID_FILE_ATTRIBUTES)continue;trace_file=_wfsopen(path,L"w",_SH_DENYWR);break;}
  if(!trace_file){trace_failed=true;return;}
  fputs("t_us,mode,dt,speed,goal_f,goal_r,goal_u,bank_r,bank_u,ff_pitch,ff_yaw,S_p,S_y,S_r,R_p,R_y,R_r,u_p,u_y,u_r,Sout_p,Sout_y,Sout_r,e_p,e_y,e_r,stop_p,stop_y,stop_r,angle,calib_pitch,calib_bank,aim_speed,aim_still\n",trace_file);
 }
 for(size_t i=0;i<count&&trace_rows<900000;++i,++trace_rows){const auto& r=batch[i];
  fprintf(trace_file,"%llu,%d,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.7g,%.7g,%.7g,%.7g,%.7g,%.7g,%.6g,%.6g,%.6g,%.7g,%.7g,%.7g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.5g,%.4g,%.4g,%.4g,%.4g\n",
   (unsigned long long)r.t,r.mode,r.dt,r.speed,r.goal[0],r.goal[1],r.goal[2],r.bank_r,r.bank_u,r.ff[0],r.ff[1],r.S[0],r.S[1],r.S[2],r.R[0],r.R[1],r.R[2],
   r.stick[0],r.stick[1],r.stick[2],r.Sout[0],r.Sout[1],r.Sout[2],r.err[0],r.err[1],r.err[2],r.stop[0],r.stop[1],r.stop[2],r.angle,r.calib_p,r.calib_b,r.aim_speed,r.aim_still);}
 fflush(trace_file);
}

// Controller state owned by the game thread (input hook).
struct Runtime {
 fe_control::Controller controller;fe_control::Tuning tuning;fe::Params params;uintptr_t params_pawn=0;uint64_t params_frame=0;
 uintptr_t pawn=0;int mode=0;uint64_t frames=0,used=0,fallbacks=0;int last_reason=0;uint32_t last_flags=0;
};
inline Runtime rt;

// War Thunder-style manual override (manual_takeover.h, AC8 2.4.2): ownership is decided every frame on the keyboard-
// only command state, simulated with the stock input filter (AC7's equivalent of WT's keyboard ramp). Manual pitch or
// yaw releases all three channels; manual roll alone releases roll only; below the threshold the instructor overrides
// the keys completely. A held key engages at 0.3 (hand-back after release at 0.8), keeps ownership through a reversal,
// and the stock command state continues from the keyboard-only state at the handover (seed) instead of re-ramping
// from the instructor's last command - AC7 has the same stock input ramp as AC8 (inadd/indec, same law).
struct Manual {manual_takeover::State s;uintptr_t pawn=0;bool seed[3]{};double seed_value[3]{};};
inline Manual manual;
inline manual_takeover::Tuning takeover_tuning=manual_takeover::war242;
// dir: held-key direction per FE axis (0 pitch, 1 yaw, 2 roll), -1/0/+1. Returns release mask: 1 pitch, 2 yaw, 4 roll.
// manual.seed[a] / seed_value[a]: continue axis a's stock command state from the keyboard-only state this frame.
inline int manual_release(uintptr_t pawn,float dt,const int dir[3]){
 if(pawn!=manual.pawn){manual=Manual{};manual.pawn=pawn;}
 for(bool& b:manual.seed)b=false;
 if(!(dt>0&&dt<.1f)||!rt.params.valid)return (dir[0]||dir[1]?7:0)|(dir[2]?4:0);   // no model: keys win at once
 return manual_takeover::step(rt.params,manual.s,dir,dt,takeover_tuning,manual.seed,manual.seed_value);
}
inline aim_motion::Estimator aim_est;inline uintptr_t aim_est_pawn=0;
struct Command {double stick[3]{};double S[3]{};bool valid=false;int reason=0;};
// reason codes: 1 params, 2 state, 3 goal, 4 calibration, 5 dt, 6 controller, 7 special flight-engine mode
inline Command compute(uintptr_t pawn,uintptr_t core,float dt,int mode,uint64_t now_us){
 Command c;++rt.frames;
 if(pawn!=rt.pawn||mode!=rt.mode){rt.controller.reset();rt.pawn=pawn;rt.mode=mode;}
 if(pawn!=rt.params_pawn||rt.frames-rt.params_frame>600||!rt.params.valid){
  unsigned char buf[P_BYTES];
  if(!read_params_raw(core,buf)||!fe::from_memory_ac7(buf,rt.params)){c.reason=1;rt.last_reason=1;++rt.fallbacks;rt.params.valid=false;return c;}
  rt.params_pawn=pawn;rt.params_frame=rt.frames;
 }
 if(!(dt>0&&dt<.1f)){c.reason=5;rt.last_reason=5;++rt.fallbacks;return c;}
 Raw raw;Quat q;
 if(!read_raw(core,raw)||!quat_of(raw,q)||!std::isfinite(raw.speed)||raw.speed<0||raw.speed>2000||raw.novice){c.reason=2;rt.last_reason=2;++rt.fallbacks;return c;}
 for(int a=0;a<3;++a)if(!std::isfinite(raw.S[a])||std::abs(raw.S[a])>1.001||!std::isfinite(raw.R[a])||std::abs(raw.R[a])>20||!std::isfinite(raw.cap[a])||raw.cap[a]<0||raw.cap[a]>20){c.reason=2;rt.last_reason=2;++rt.fallbacks;return c;}
 rt.last_flags=raw.flags;
 if(raw.flags&SPECIAL_FLAGS){rt.controller.reset();c.reason=7;rt.last_reason=7;++rt.fallbacks;return c;}
 if(calib_bad.load()>120){c.reason=4;rt.last_reason=4;++rt.fallbacks;return c;}
 Goal g;{std::lock_guard<std::mutex> l(goal_mutex);g=goal;}
 if(!g.valid||g.pawn!=pawn){c.reason=3;rt.last_reason=3;++rt.fallbacks;return c;}
 // Target in the current FE body frame via the attitude change since the Lua sample.
 const auto world=rot(g.q,fe_from_mod(g.body));const auto now_b=mod_from_fe(rot(conj(q),world));
 const auto up_r=-rot(q,{1,0,0}).y,up_u=rot(q,{0,1,0}).y,up_f=rot(q,{0,0,1}).y;
 fe_control::Geometry geo;geo.goal=now_b;geo.bank_r=up_r;geo.bank_u=up_u;geo.up_f=up_f;geo.ff_pitch=g.ff_pitch;geo.ff_yaw=g.ff_yaw;geo.mot_up=g.mot_up;geo.mot_right=g.mot_right;
 for(int a=0;a<3;++a)geo.cap[a]=raw.cap[a];geo.cap_valid=true;
 // Windowed aim motion in the world (FE) frame, expressed in the current mod body axes.
 if(pawn!=aim_est_pawn){aim_est.reset();aim_est_pawn=pawn;}
 aim_est.update(double(now_us)*1e-6,world);
 {const auto vb=mod_from_fe(rot(conj(q),aim_est.vel));geo.aim_speed=float(aim_est.speed);geo.aim_still=float(aim_est.still);geo.aim_up=vb.z;geo.aim_right=vb.y;geo.aim_path=float(aim_est.path_speed);geo.aim_moving=float(aim_est.moving);geo.aim_quiet=float(aim_est.quiet);}
 double Sm[3],Rm[3];for(int a=0;a<3;++a){Sm[a]=raw.S[a]*MIRROR[a];Rm[a]=raw.R[a]*MIRROR[a];}
 const auto o=rt.controller.step(rt.params,Sm,Rm,raw.speed,dt,geo,mode==5?fe_control::Mode::Direct:fe_control::Mode::Stick,rt.tuning);
 if(!o.valid){c.reason=6;rt.last_reason=6;++rt.fallbacks;return c;}
 for(int a=0;a<3;++a){c.stick[a]=o.stick[a]*MIRROR[a];c.S[a]=o.S[a]*MIRROR[a];}   // back to FE signs
 c.valid=true;rt.last_reason=0;++rt.used;
 Record r{};r.t=now_us;r.mode=mode;r.dt=dt;r.speed=raw.speed;r.goal[0]=geo.goal.x;r.goal[1]=geo.goal.y;r.goal[2]=geo.goal.z;r.bank_r=up_r;r.bank_u=up_u;r.ff[0]=g.ff_pitch;r.ff[1]=g.ff_yaw;
 for(int a=0;a<3;++a){r.S[a]=raw.S[a];r.R[a]=raw.R[a];r.stick[a]=c.stick[a];r.Sout[a]=c.S[a];r.err[a]=o.errors[a];r.stop[a]=o.stop[a];}
 r.angle=float(o.angle);r.calib_p=calib_pitch_err.load();r.calib_b=calib_bank_err.load();r.aim_speed=geo.aim_speed;r.aim_still=geo.aim_still;trace_push(r);
 return c;
}

}
