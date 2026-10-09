#pragma once
#include "vendor/ue4ss/LuaMadeSimple.hpp"
#include <bcrypt.h>
#pragma comment(lib, "bcrypt.lib")

// Only use the public exported LuaMadeSimple API, never lua_State internals.
// Header is a snapshot of the supplied UE4SS source (fmt -> std::format only).
// The bundled runtime is pinned before constructing any C++ Lua wrapper.
inline bool compatible_lua_runtime() {
    HMODULE module=GetModuleHandleW(L"UE4SS.dll");
    wchar_t path[MAX_PATH]{};
    if (!module || !GetModuleFileNameW(module,path,MAX_PATH)) return false;
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,0,nullptr);
    if (file==INVALID_HANDLE_VALUE) return false;
    BCRYPT_ALG_HANDLE alg=nullptr;
    BCRYPT_HASH_HANDLE hash=nullptr;
    bool ok=BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0;
    if (ok) ok=BCryptCreateHash(alg,&hash,nullptr,0,nullptr,0,0)>=0;
    unsigned char buffer[65536],digest[32]{};
    DWORD read=0;
    while (ok) {
        if (!ReadFile(file,buffer,sizeof(buffer),&read,nullptr)) { ok=false; break; }
        if (!read) break;
        ok=BCryptHashData(hash,buffer,read,0)>=0;
    }
    if (ok) ok=BCryptFinishHash(hash,digest,sizeof(digest),0)>=0;
    if (hash) BCryptDestroyHash(hash);
    if (alg) BCryptCloseAlgorithmProvider(alg,0);
    CloseHandle(file);
    constexpr unsigned char expected[32]={0x7C,0x62,0x19,0xD0,0xB1,0x3B,0x7F,0xCF,0xFC,0xE5,0x9F,0x5B,0x62,0x11,0x1A,0x78,0x3E,0xB6,0x4E,0x02,0xB2,0x06,0xDB,0xF8,0xD4,0x35,0x17,0xE7,0xEB,0x54,0x0A,0xCD};
    return ok && memcmp(digest,expected,sizeof(expected))==0;
}
using LuaView=RC::LuaMadeSimple::Lua;
// Verified bundled constructor: registry reference at +0xA0, total 0xA8.
static_assert(sizeof(LuaView)==0xA8 && alignof(LuaView)==8,"UE4SS Lua wrapper ABI changed");
template<size_t N> bool read_numbers(const LuaView& lua,double (&args)[N]) {
    if (lua.get_stack_size()!=N) return false;
    // get_number removes the value, so pop in reverse order.
    for (size_t i=N;i>0;--i) {
        if (!lua.is_number(-1)) return false;
        args[i-1]=lua.get_number(-1);
        if (!std::isfinite(args[i-1])) return false;
    }
    return true;
}
inline bool live_pointer_number(double n) {
    return n>=65536 && n<=static_cast<double>(0x00007fffffff0000ull) &&
        n==std::floor(n) && (static_cast<uintptr_t>(n)&7)==0;
}
