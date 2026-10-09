#pragma once
// Only used with individually verified, complete, non-relative prologues.
inline bool ac7_hook(void* target,void* replacement,void** original,const unsigned char* expected,size_t size){
 if(memcmp(target,expected,size))return false;
 auto init=MH_Initialize();if(init!=MH_OK&&init!=MH_ERROR_ALREADY_INITIALIZED)return false;
 auto result=MH_CreateHook(target,replacement,original);
 if(result==MH_OK)return MH_EnableHook(target)==MH_OK;
 if(result!=MH_ERROR_MEMORY_ALLOC||size<14)return false;
 auto code=static_cast<unsigned char*>(target);
 auto trampoline=static_cast<unsigned char*>(VirtualAlloc(nullptr,size+14,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE));if(!trampoline)return false;
 auto jump=[](unsigned char* p,void* to){p[0]=0xff;p[1]=0x25;*reinterpret_cast<unsigned*>(p+2)=0;*reinterpret_cast<void**>(p+6)=to;};
 memcpy(trampoline,code,size);jump(trampoline+size,code+size);DWORD old;
 if(!VirtualProtect(trampoline,size+14,PAGE_EXECUTE_READ,&old)){VirtualFree(trampoline,0,MEM_RELEASE);return false;}
 FlushInstructionCache(GetCurrentProcess(),trampoline,size+14);
 if(!VirtualProtect(code,size,PAGE_EXECUTE_READWRITE,&old)){VirtualFree(trampoline,0,MEM_RELEASE);return false;}
 *original=trampoline;jump(code,replacement);memset(code+14,0x90,size-14);FlushInstructionCache(GetCurrentProcess(),code,size);
 DWORD ignored;VirtualProtect(code,size,old,&ignored);return true;
}
