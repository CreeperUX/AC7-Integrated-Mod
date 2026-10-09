// AC7 0.5.2 GPU reticle: AC8 2.4.1 geometry drawn by the overlay at native resolution.
// 1. connector-tick geometry equals native_hud.lua; 2. hidden hardware render at 3840x2160 with pixel checks for the ring,
// HMD brackets, free-look ring, gun cross and ticks; raw BGRA dumps go to test-runtime/previews for visual review.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wrl/client.h>
#include <d3d11.h>
#include <dxgi1_3.h>
#include <d2d1_1.h>
#include <dcomp.h>
#include <dwrite.h>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "src/gpu_hud_renderer.h"
#pragma comment(lib,"dwrite.lib")
#pragma comment(lib,"d3d11.lib")
#pragma comment(lib,"dxgi.lib")
#pragma comment(lib,"d2d1.lib")
#pragma comment(lib,"dcomp.lib")
#pragma comment(lib,"ole32.lib")
#pragma comment(lib,"user32.lib")
#define REQUIRE(c) do{if(!(c)){printf("FAIL %s:%d %s\n",__FILE__,__LINE__,#c);exit(1);}}while(0)
static void check(HRESULT hr,const char* stage){if(FAILED(hr)){printf("FAIL %s %08lX\n",stage,(unsigned long)hr);exit(1);}}
static bool close_to(float a,float b,float tol){return std::fabs(a-b)<=tol;}

struct Image {UINT w=0,h=0;std::vector<unsigned char> px;
    const unsigned char* at(float x,float y)const{return &px[(size_t(y)*w+size_t(x))*4];}
    // Cyan core: sRGB 88,203,225 at the shape alpha .85, premultiplied (BGRA), over the dark edge (alpha .75 x .85).
    bool core_px(float x,float y)const{auto c=at(x,y);
        return c[3]>=230&&close_to(c[2],88*.85f,10)&&close_to(c[1],203*.85f,10)&&close_to(c[0],225*.85f,10);}
    // A fully covered core pixel within 1.5 px (thin strokes need not cover the exact sample point on a diagonal).
    bool core(float x,float y)const{for(float dy=-1;dy<=1;++dy)for(float dx=-1;dx<=1;++dx)if(core_px(x+dx,y+dy))return true;return false;}
    bool clear(float x,float y)const{return at(x,y)[3]==0;}
    // Any reticle pixel within r of (x,y).
    bool ink(float x,float y,float r)const{for(float dy=-r;dy<=r;++dy)for(float dx=-r;dx<=r;++dx)if(at(x+dx,y+dy)[3])return true;return false;}
};
static Image dump(gpu_hud::Renderer& r,const char* path){
    Microsoft::WRL::ComPtr<ID3D11Texture2D> source,staging;
    check(r.swap->GetBuffer(0,IID_PPV_ARGS(source.GetAddressOf())),"get backbuffer");
    D3D11_TEXTURE2D_DESC desc{};source->GetDesc(&desc);desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;desc.MiscFlags=0;
    check(r.device->CreateTexture2D(&desc,nullptr,staging.GetAddressOf()),"staging");r.immediate->CopyResource(staging.Get(),source.Get());
    D3D11_MAPPED_SUBRESOURCE map{};check(r.immediate->Map(staging.Get(),0,D3D11_MAP_READ,0,&map),"map");
    Image img;img.w=desc.Width;img.h=desc.Height;img.px.resize(size_t(img.w)*img.h*4);
    for(UINT y=0;y<img.h;++y)memcpy(&img.px[size_t(y)*img.w*4],static_cast<unsigned char*>(map.pData)+y*map.RowPitch,img.w*4);
    r.immediate->Unmap(staging.Get(),0);
    for(size_t i=0;i<img.px.size();i+=4)REQUIRE(img.px[i]<=img.px[i+3]+1&&img.px[i+1]<=img.px[i+3]+1&&img.px[i+2]<=img.px[i+3]+1);
    FILE* f=nullptr;fopen_s(&f,path,"wb");REQUIRE(f);fwrite(img.px.data(),1,img.px.size(),f);fclose(f);return img;
}

int main(){
    namespace R=hud_geometry::reticle;
    // ---- 1. geometry, against native_hud.lua at 1080p: ring (960,540), nose (1000,600) ----
    REQUIRE(close_to(R::unit(2160),120.f/128,1e-6f)&&close_to(R::unit(1080),60.f/128,1e-6f));
    {auto t=R::ticks({960,540},{1000,600},1080,false);
     const float d=std::hypot(40.f,60.f),ux=40/d,uy=60/d,start=24.375f;   // 120*1080/2160*.5*.8125
     const float off[3]={start+8,start+18,start+28},op[3]={.85f,std::min(1.f,(d-off[1]-16)/14)*.84f*.85f,std::min(1.f,(d-off[2]-16)/14)*.68f*.85f};
     for(int i=0;i<3;++i){REQUIRE(close_to(t[i].center.x,960+ux*off[i],1e-3f)&&close_to(t[i].center.y,540+uy*off[i],1e-3f));
        REQUIRE(close_to(t[i].opacity,op[i],1e-4f));REQUIRE(close_to(t[i].across.x*ux+t[i].across.y*uy,0,1e-6f));}
     auto a=R::ticks({960,540},{1000,600},1080,true);REQUIRE(close_to(a[2].opacity,.68f*.85f,1e-5f));
     auto none=R::ticks({960,540},{970,545},1080,false);for(auto& x:none)REQUIRE(x.opacity==0);
     auto bad=R::ticks({960,540},{NAN,0},1080,false);for(auto& x:bad)REQUIRE(x.opacity==0);}
    {unsigned cases=0;for(float h:{720.f,1080.f,1440.f,2160.f})for(int a=0;a<360;a+=5)for(int d=0;d<2000;d+=7){
        float rad=a*3.14159265f/180;hud_geometry::Point n{float(d)*cosf(rad),float(d)*sinf(rad)};
        for(auto& t:R::ticks({0,0},n,h,false)){REQUIRE(std::isfinite(t.opacity)&&t.opacity>=0&&t.opacity<=.85f+1e-6f);
            if(t.opacity){const float s=std::max(.75f,h/1080);REQUIRE(std::hypot(t.center.x,t.center.y)>R::ring*R::unit(h));REQUIRE(std::hypot(n.x-t.center.x,n.y-t.center.y)>=16*s-.01f);}}
        ++cases;}
     printf("PASS reticle geometry: native_hud.lua tick positions/opacity, %u sweep cases\n",cases);}

    // ---- 2. hidden hardware render at 3840x2160 ----
    check(CoInitializeEx(nullptr,COINIT_MULTITHREADED),"COM");
    WNDCLASSW wc{};wc.lpfnWndProc=DefWindowProcW;wc.hInstance=GetModuleHandleW(nullptr);wc.lpszClassName=L"AC7ReticleTest";REQUIRE(RegisterClassW(&wc));
    HWND w=CreateWindowExW(WS_EX_NOREDIRECTIONBITMAP|WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,wc.lpszClassName,L"Hidden reticle test",WS_POPUP,0,0,640,360,nullptr,nullptr,wc.hInstance,nullptr);REQUIRE(w);
    REQUIRE(SetLayeredWindowAttributes(w,0,255,LWA_ALPHA));
    {
        gpu_hud::Renderer r;check(r.initialize(w,3840,2160,L"test-runtime\\ui-fonts"),"hardware initialize");
        const float k=R::unit(2160);const hud_geometry::Point ring{1920,1080},nose{2240,1300},look{1500,900};
        auto frame=[&](bool hmd,bool freelook,bool cross,bool connector,const char* path,float width=1){
            REQUIRE(WaitForSingleObject(r.latency,1000)==WAIT_OBJECT_0);
            gpu_hud::Layout f;f.target=f.nose=true;f.target_point=ring;f.nose_point=nose;f.helmet_active=hmd;f.freelook=freelook;
            f.look=hmd&&freelook;f.look_point=look;f.boresight_active=cross;f.connector=connector;f.opacity=.65f;f.line_width=width;
            check(r.draw(f,1.f/120),"draw");Image img=dump(r,path);check(r.present(),"present");return img;
        };
        const float c45=std::cos(45*3.14159265f/180);
        // plain flight: ring + gun cross + ticks; clear centres; no brackets
        auto a=frame(false,false,true,true,"test-runtime/previews/reticle-4k-plain.bgra");
        REQUIRE(a.core(ring.x+R::ring*k,ring.y)&&a.core(ring.x,ring.y-R::ring*k)&&a.clear(ring.x,ring.y)&&!a.ink(ring.x,ring.y,25));
        REQUIRE(a.core(nose.x+18*k,nose.y)&&a.core(nose.x,nose.y-18*k)&&a.clear(nose.x,nose.y));
        REQUIRE(!a.ink(ring.x+R::bracket_radius*k*c45,ring.y-R::bracket_radius*k*c45,1));
        {auto t=R::ticks(ring,nose,2160,false);REQUIRE(t[0].opacity>0&&a.ink(t[0].center.x,t[0].center.y,1));}
        // stroke widths at 4K: core 3.15k (2.95 px) with a 1k (0.94 px) dark edge -> ink spans about 5 px across the ring
        auto span=[&](const Image& m){int n=0;for(float x=ring.x+R::ring*k-8;x<=ring.x+R::ring*k+8;++x)if(m.at(x,ring.y)[3]>64)++n;return n;};
        REQUIRE(close_to(R::core_width(k,1),2.953f,.01f)&&close_to(R::dark_width(k,1),4.828f,.01f));
        {const int n=span(a);REQUIRE(n>=4&&n<=6);}
        // hud_line_width scales the core (0.5..2, clamped), the dark edge stays
        {auto thin=frame(false,false,true,true,"test-runtime/previews/reticle-4k-width05.bgra",.5f);auto wide=frame(false,false,true,true,"test-runtime/previews/reticle-4k-width2.bgra",2);
         auto huge=frame(false,false,true,true,"test-runtime/previews/reticle-4k-width9.bgra",9);
         const int n0=span(thin),n2=span(wide),n9=span(huge);REQUIRE(n0>=3&&n0<=4&&n2>=7&&n2<=9&&n9==n2);REQUIRE(wide.core(ring.x+R::ring*k,ring.y));}
        // HMD: bracketed ring at the cursor
        auto b=frame(true,false,true,true,"test-runtime/previews/reticle-4k-hmd.bgra");
        REQUIRE(b.core(ring.x+R::bracket_radius*k*c45,ring.y-R::bracket_radius*k*c45)&&b.core(ring.x+R::hmd_ring*k,ring.y));
        REQUIRE(!b.ink(look.x+R::hmd_ring*k,look.y,2));
        // HMD + C free look: plain cursor ring plus the bracketed look ring
        auto c=frame(true,true,true,true,"test-runtime/previews/reticle-4k-hmd-freelook.bgra");
        REQUIRE(!c.ink(ring.x+R::bracket_radius*k*c45,ring.y-R::bracket_radius*k*c45,1)&&c.core(ring.x+R::ring*k,ring.y));
        REQUIRE(c.core(look.x+R::hmd_ring*k,look.y)&&c.core(look.x-R::bracket_radius*k*c45,look.y+R::bracket_radius*k*c45));
        // gun cross hidden (Alt+F7 / hud_boresight=0), connector off (hud_connector=0)
        auto d=frame(false,false,false,false,"test-runtime/previews/reticle-4k-nocross.bgra");
        REQUIRE(!d.ink(nose.x+18*k,nose.y,2)&&d.core(ring.x+R::ring*k,ring.y));
        {auto t=R::ticks(ring,nose,2160,false);REQUIRE(!d.ink(t[0].center.x,t[0].center.y,2));}
        // UI-only frame (hybrid mode 3) draws no reticle
        REQUIRE(WaitForSingleObject(r.latency,1000)==WAIT_OBJECT_0);
        {gpu_hud::Layout f;f.ui_only=true;f.target=f.nose=true;f.target_point=ring;f.nose_point=nose;check(r.draw(f,1.f/120),"ui only");
         Image e=dump(r,"test-runtime/previews/reticle-4k-uionly.bgra");check(r.present(),"present");for(size_t i=3;i<e.px.size();i+=4)REQUIRE(e.px[i]==0);}
        printf("PASS hardware render 3840x2160: ring/HMD/free-look/gun cross/ticks, thin strokes + hud_line_width 0.5/2/clamp, clear centres, toggles, UI-only\n");
    }
    DestroyWindow(w);UnregisterClassW(wc.lpszClassName,wc.hInstance);CoUninitialize();
}
