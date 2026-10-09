#pragma once
#include "ac7_camera_anchor.h"
// AC7 camera getters were independently resolved from reflected UFunctions.
// Their live code reads float location at +0x400 and rotation at +0x40C.
// The renderer also reads the cache directly; getter-only overrides are insufficient.
// Apply the final POV after native DoUpdateCamera completes, keeping FOV/effects intact.
using CameraVectorGetter=float*(__fastcall*)(void*,float*);
using CameraViewGetter=void(__fastcall*)(void*,float*,float*);
CameraVectorGetter original_camera_location=nullptr,original_camera_rotation=nullptr;
CameraViewGetter original_camera_view=nullptr;
using CameraUpdate=void(__fastcall*)(void*,float);
CameraUpdate original_camera_update=nullptr;
struct CameraCommand{uintptr_t manager=0,pawn=0;double p=0,y=0,r=0,x=0,ly=0,z=0;ULONGLONG tick=0;};
// Free-look zoom (C + zoom key), same bounded optical envelope as the AC8 build's custom zoom: hold >= 0.18 s,
// smooth 12/s blend, twofold baseline magnification expanded by free_look_zoom. FOV lives in CameraCache.POV +0x418
// (after location +0x400 and rotation +0x40C); verified against the reflected GetFOVAngle value from Lua before use.
struct CustomZoomEnvelope {
 float hold_seconds=0,weight=0;
 void reset(){hold_seconds=weight=0;}
 float step(float original,float factor,bool held,float dt){
  if(!std::isfinite(original)||original<5||original>170||!std::isfinite(factor)||factor<1||factor>3||!std::isfinite(dt)||dt<=0||dt>.25f){reset();return original;}
  hold_seconds=held?hold_seconds+dt:0;
  float goal=held&&hold_seconds>=.18f?1.f:0.f;
  weight+=(goal-weight)*(1-std::exp(-12*dt));weight=std::clamp(weight,0.f,1.f);
  if(!held&&weight<.001f){weight=0;return original;}
  if(weight==0)return original;
  float result=2*std::atan(std::tan(original*.5f*flight::rad)/(1+factor*weight))/flight::rad;
  return std::clamp(result,std::min(15.f,original),original);
 }
};
CustomZoomEnvelope custom_zoom;
int fov_check_good=0,fov_check_bad=0;bool fov_offset_verified=false,fov_offset_rejected=false;
float camera_dt=1.f/60;
std::mutex camera_command_mutex;CameraCommand camera_command;
std::atomic<uint64_t> camera_view_calls{0},camera_applied_calls{0};
uint64_t camera_anchor_failures=0,camera_anchor_samples=0,camera_anchor_report=0;
uintptr_t camera_rig_owner=0;flight::V camera_rig_local{-300,0,60};bool camera_rig_calibrated=false;
double camera_anchor_lag_sum=0;float camera_anchor_lag_peak=0;
bool receive_camera(uintptr_t manager,uintptr_t pawn,double p,double y,double r,double x,double ly,double z){
 for(double v:{p,y,r,x,ly,z})if(!std::isfinite(v)||std::abs(v)>1e10)return false;
 std::unique_lock<std::mutex> lock(camera_command_mutex,std::try_to_lock);if(!lock.owns_lock())return false;
 camera_command={manager,pawn,p,y,r,x,ly,z,GetTickCount64()};return true;
}
bool camera_values(void* manager,float* position,float* rotation,float* fov_out=nullptr){
 if(!running.load()||!active.load()||!enabled.load()||game_paused.load()||gaze_active.load()||context_suspended.load()||!foreground_is_game())return false;
 CameraCommand c;{std::unique_lock<std::mutex> lock(camera_command_mutex,std::try_to_lock);if(!lock.owns_lock())return false;c=camera_command;}
 if(!c.manager||reinterpret_cast<uintptr_t>(manager)!=c.manager||c.pawn!=aircraft.load()||GetTickCount64()-c.tick>150||GetTickCount64()-pose_tick.load()>150)return false;
 flight::V live;
 if(!ac7_camera::read_live_position(c.pawn,live)){++camera_anchor_failures;return false;}
 const auto axes=flight::basis(float(c.p),float(c.y),float(c.r));
 // Anchor at the CURRENT post-physics transform, not Lua's earlier-frame pose.
 if(native_rig_reset_requested.exchange(false)||camera_rig_owner!=c.pawn){camera_rig_owner=c.pawn;camera_rig_calibrated=false;camera_rig_local={-300,0,60};custom_zoom.reset();}
 if(!manual_camera_active.load()){
  // The original update has just written this frame's unmodified native POV.
  float native[6];memcpy(native,static_cast<unsigned char*>(manager)+0x400,sizeof(native));
  bool finite=true;for(float v:native)finite=finite&&std::isfinite(v)&&std::abs(v)<1e9;
  if(finite){
   auto original_axes=flight::basis(native[3],native[4],native[5]);
   auto d=flight::V{native[0],native[1],native[2]}-live;
   auto local=flight::V{flight::dot(d,original_axes.f),flight::dot(d,original_axes.r),flight::dot(d,original_axes.u)};
   if(local.x<-10&&flight::dot(local,local)<4000000){camera_rig_local=local;camera_rig_calibrated=true;}
  }
 }
 const auto local=camera_view_mode.load()==0?camera_rig_local:flight::V{-camera_distance_cm.load()*.1f,0,camera_height_cm.load()*.1f};
 const auto offset=axes.f*local.x+axes.r*local.y+axes.u*local.z;
 const auto eye=live+offset;
 if(position){position[0]=eye.x;position[1]=eye.y;position[2]=eye.z;}
 // FOV: verify the cache offset once against Lua's GetFOVAngle (view_fov), then apply the free-look zoom.
 float fov=0;memcpy(&fov,static_cast<unsigned char*>(manager)+0x418,sizeof(fov));
 if(!fov_offset_verified&&!fov_offset_rejected&&std::isfinite(fov)){
  if(std::abs(fov-view_fov.load())<.05f){if(++fov_check_good>=30){fov_offset_verified=true;log_line("CAMERA_FOV offset 0x418 verified (fov=%.2f); free-look zoom available",fov);}}
  else if(++fov_check_bad>=30){fov_offset_rejected=true;log_line("CAMERA_FOV offset 0x418 rejected (cache %.2f vs reflected %.2f); free-look zoom disabled",fov,view_fov.load());}
 }
 if(fov_offset_verified&&std::isfinite(fov)&&fov>=5&&fov<=170){
  const auto bindings=keybindings.load();auto held=[](int key){return (GetAsyncKeyState(key)&0x8000)!=0;};
  const bool zooming=manual_camera_active.load()&&foreground_is_game()&&custom_keys::down(bindings,custom_keys::Action::FreeLook,held)&&custom_keys::down(bindings,custom_keys::Action::Zoom,held);
  const float zoomed=custom_zoom.step(fov,free_look_zoom.load(),zooming,camera_dt);
  if(fov_out)*fov_out=zoomed;
  effective_camera_fov=zoomed;effective_fov_manager=reinterpret_cast<uintptr_t>(manager);effective_fov_tick=GetTickCount64();
 }
 if(rotation){rotation[0]=float(c.p);rotation[1]=float(c.y);rotation[2]=float(c.r);}
 const auto lag=live-flight::V{float(c.x),float(c.ly),float(c.z)};
 const float distance=std::sqrt(flight::dot(lag,lag))*.1f;
 camera_anchor_lag_sum+=distance;camera_anchor_lag_peak=std::max(camera_anchor_lag_peak,distance);++camera_anchor_samples;
 auto now=GetTickCount64();
 if(now-camera_anchor_report>=5000){
  log_line("CAMERA_LIVE_ANCHOR samples=%llu lua_position_lag_mean_m=%.4f peak_m=%.4f invalid_reads=%llu; same-frame anchor active",camera_anchor_samples,camera_anchor_samples?camera_anchor_lag_sum/camera_anchor_samples:0,camera_anchor_lag_peak,camera_anchor_failures);
  camera_anchor_report=now;camera_anchor_samples=0;camera_anchor_lag_sum=0;camera_anchor_lag_peak=0;
 }
 HudFrame frame;
 if(read_pending_hud_frame(frame)&&frame.pawn==c.pawn){
  frame.cp=float(c.p);frame.cy=float(c.y);frame.cr=float(c.r);
  // The shared flight/HUD geometry uses centimetres, matching AC8's contract.
  frame.ox=offset.x*10;frame.oy=offset.y*10;frame.oz=offset.z*10;
  if(fov_offset_verified&&GetTickCount64()-effective_fov_tick.load()<250)frame.fov=effective_camera_fov.load();
  publish_hud_frame(frame);
 }
 return true;
}
float* __fastcall ac7_camera_location(void* manager,float* output){auto result=original_camera_location(manager,output);camera_values(manager,output,nullptr);return result;}
float* __fastcall ac7_camera_rotation(void* manager,float* output){auto result=original_camera_rotation(manager,output);camera_values(manager,nullptr,output);return result;}
void __fastcall ac7_camera_view(void* manager,float* location,float* rotation){
 original_camera_view(manager,location,rotation);++camera_view_calls;
 if(camera_values(manager,location,rotation))++camera_applied_calls;
}
void __fastcall ac7_camera_update(void* manager,float dt){
 original_camera_update(manager,dt);++camera_view_calls;
 float pov[6]{},fov=0;camera_dt=dt;
 if(camera_values(manager,pov,pov+3,&fov)){
  // Reflection and native writer independently agree: CameraCache.POV at +0x400.
  memcpy(static_cast<unsigned char*>(manager)+0x400,pov,sizeof(pov));
  if(fov>=5&&fov<=170)memcpy(static_cast<unsigned char*>(manager)+0x418,&fov,sizeof(fov));
  ++camera_applied_calls;
 }
}
bool install_native_camera(){
 auto base=reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
 const unsigned char loc[]={0x8b,0x81,0x08,0x04,0,0,0xf2,0x0f,0x10,0x81,0,0x04,0,0};
 const unsigned char rot[]={0x8b,0x81,0x14,0x04,0,0,0xf2,0x0f,0x10,0x81,0x0c,0x04,0,0};
 const unsigned char view[]={0xf2,0x0f,0x10,0x81,0,0x04,0,0,0xf2,0x0f,0x11,0x02,0x8b,0x81,0x08,0x04,0,0};
 // Validate all three before installing any one of them.
 if(memcmp(base+0x1989f50,loc,sizeof(loc))||memcmp(base+0x1989f70,rot,sizeof(rot))||memcmp(base+0x1989f90,view,sizeof(view))){log_line("AC7 camera signature mismatch");return false;}
 const unsigned char update[]={0x4c,0x8b,0xdc,0x55,0x49,0x8d,0xab,0x98,0xfa,0xff,0xff,0x48,0x81,0xec,0x60,0x06,0,0};
 const unsigned char root_getter[]={0x48,0x8b,0x81,0x60,0x01,0,0};
 const unsigned char translation_getter[]={0x0f,0x28,0x88,0x90,0x01,0,0};
 if(memcmp(base+0x1b23399,root_getter,sizeof(root_getter))||memcmp(base+0x1b233a5,translation_getter,sizeof(translation_getter))){log_line("AC7 live camera anchor layout mismatch");return false;}
 bool ok=ac7_hook(base+0x1985e20,reinterpret_cast<void*>(&ac7_camera_update),reinterpret_cast<void**>(&original_camera_update),update,sizeof(update));
 log_line("AC7 CAMERA_FINAL_CACHE registered=%d RVA=1985E20 POV=400 LIVE_ANCHOR=160/190; activation requires local manager and fresh command",ok?1:0);return ok;
}
