#pragma once
// AC7 build 9855922, independently resolved through UFunction wrappers.
// Unlike AC8, SelectTarget has no override parameter. OnTargetSelectReleased
// is a complete, verified 29-byte tail-call wrapper. Preserve its native gate
// and call SelectTarget(false), supplying only its pending NextTarget input.
namespace helmet {
struct Snapshot{uintptr_t pawn=0,component=0,selected=0,candidate=0;uint64_t tick=0;};
Snapshot snapshot;bool supported=false;
using Select=uintptr_t(__fastcall*)(uintptr_t,bool);
Select select_native=nullptr;
bool member(const Snapshot& s,uintptr_t component){
 __try{
  if(!s.candidate||s.component!=component||s.pawn!=aircraft.load())return false;
  if(*reinterpret_cast<uintptr_t*>(component+0x248)!=s.selected)return false;
  auto data=*reinterpret_cast<const uintptr_t**>(component+0x3b0);
  int count=*reinterpret_cast<const int*>(component+0x3b8);
  if(!data||count<0||count>4096)return false;
  for(int i=0;i<count;++i)if(data[i]==s.candidate)return true;
 }__except(EXCEPTION_EXECUTE_HANDLER){}
 return false;
}
void __fastcall release(uintptr_t pawn){
 // Same field reads and guards as the verified original wrapper.
 if(!*reinterpret_cast<const unsigned char*>(pawn+0xe14))return;
 auto component=*reinterpret_cast<const uintptr_t*>(pawn+0x1310);if(!component)return;
 const auto s=snapshot;
 const bool eligible=on_bridge_thread()&&helmet_enabled.load()&&enabled.load()&&active.load()&&
  !game_paused.load()&&!gaze_active.load()&&!context_suspended.load()&&foreground_is_game()&&
  s.pawn==pawn&&GetTickCount64()-s.tick<=100&&member(s,component);
 if(!eligible){select_native(component,false);return;}
 auto pending=reinterpret_cast<uintptr_t*>(component+0x258);const auto previous=*pending;
 *pending=s.candidate;snapshot={};
 auto result=select_native(component,false); // Keeps native hold-time and lock rules.
 if(*pending==s.candidate)*pending=previous; // Restore when native selection declined.
 log_line("HMD_SELECT candidate=%llX selected=%llX accepted=%d",s.candidate,result,result==s.candidate);
}
bool install(){
 auto base=reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));
 const unsigned char wrapper[]={0x80,0xb9,0x14,0x0e,0,0,0,0x74,0x13,0x48,0x8b,0x89,0x10,0x13,0,0,0x48,0x85,0xc9,0x74,0x07,0x33,0xd2,0xe9,0x64,0x66,0xca,0xff,0xc3};
 const unsigned char select[]={0x40,0x57,0x48,0x83,0xec,0x30,0xf3,0x0f,0x10,0x81,0xe0,0x01,0,0};
 if(memcmp(base+0x822a30,wrapper,sizeof(wrapper))||memcmp(base+0x4c90b0,select,sizeof(select))){log_line("HMD unavailable: AC7 signature mismatch");return false;}
 auto target=base+0x822a30;DWORD old;
 if(!VirtualProtect(target,14,PAGE_EXECUTE_READWRITE,&old))return false;
 select_native=reinterpret_cast<Select>(base+0x4c90b0);
 target[0]=0xff;target[1]=0x25;*reinterpret_cast<unsigned*>(target+2)=0;
 *reinterpret_cast<void**>(target+6)=reinterpret_cast<void*>(&release);
 FlushInstructionCache(GetCurrentProcess(),target,14);DWORD ignored;VirtualProtect(target,14,old,&ignored);
 supported=true;log_line("HMD ready: AC7 native release wrapper verified; F2 toggle");return true;
}
}
