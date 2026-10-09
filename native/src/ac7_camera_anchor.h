#pragma once
#include "flight_math.h"
namespace ac7_camera {
// Build 9855922: K2_GetActorLocation reads RootComponent +0x160, then
// ComponentToWorld.Translation +0x190. Verified independently from live code.
inline bool read_live_position(uintptr_t pawn,flight::V& result){
 __try{
  if(pawn<65536)return false;
  auto root=*reinterpret_cast<const uintptr_t*>(pawn+0x160);
  if(root<65536||(root&7))return false;
  const float* p=reinterpret_cast<const float*>(root+0x190);
  const flight::V value{p[0],p[1],p[2]};
  if(!std::isfinite(value.x)||!std::isfinite(value.y)||!std::isfinite(value.z)||
     std::abs(value.x)>1e9f||std::abs(value.y)>1e9f||std::abs(value.z)>1e9f)return false;
  result=value;return true;
 }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
inline flight::V position(flight::V live,const flight::Basis& view){return live-view.f*300.f+view.u*60.f;}
}
