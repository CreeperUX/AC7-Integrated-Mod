#pragma once
#include <cmath>
#include <algorithm>
#include <array>
namespace hud_geometry {
struct Point {float x=0,y=0;};
constexpr float ring_radius=21.f;
struct Tick {Point a,b;float opacity=0;};
struct Link {std::array<Tick,3> ticks{};};
// Three transverse ticks on the nose-facing side of the target ring.
// Spatial indication only: no timed animation or filtered mouse position.
inline Link connector(Point nose,Point target,float scale,bool always){
    Link out;float dx=nose.x-target.x,dy=nose.y-target.y,distance=std::hypot(dx,dy);
    if(!std::isfinite(distance)||!std::isfinite(scale)||scale<=0||distance<=.001f)return out;
    float ux=dx/distance,uy=dy/distance;
    float spacing=std::clamp(distance*.03f,10.f*scale,18.f*scale);
    for(int i=0;i<3;++i){
        float offset=27.f*scale+i*spacing;
        float available=distance-offset-16.f*scale;
        if(available<=0)continue;
        float fade=always?1.f:std::clamp(available/(14.f*scale),0.f,1.f);
        Point center{target.x+ux*offset,target.y+uy*offset};float half=3.f*scale;
        out.ticks[i]={{center.x-uy*half,center.y+ux*half},{center.x+uy*half,center.y-ux*half},fade*(1.f-.16f*i)};
    }
    return out;
}
// AC8 2.4.1 reticle geometry (lua/make_reticles.py and AC7 native_hud.lua): a 128-unit texture drawn 120 px tall at
// 2160p. Ring centre radius 48; HMD ring 47.75 with brackets of +-14 degrees at radius 58.5 on the diagonals; gun-cross
// arms 8..28 units from the nose point. Strokes (AC7, tuned in flight at 4K: the AC8 textures' 4-unit core over 8 units
// of dark read too heavy, 2.25 too thin, 3.15 = 2.25 x 1.4 accepted): 3.15-unit core times hud_line_width, with a
// 1-unit dark edge each side.
namespace reticle {
constexpr float core=3.15f,edge=1,dark_alpha=.75f,ring=48,hmd_ring=47.75f,bracket_radius=58.5f,bracket_half_deg=14,cross_inner=8,cross_outer=28;
inline float unit(float height){return 120.f*height/2160.f/128.f;}
inline float shape_alpha(float opacity){return std::max(.85f,std::clamp(opacity,0.f,1.f));}
inline float line_scale(float width){return std::isfinite(width)?std::clamp(width,.5f,2.f):1.f;}
inline float core_width(float k,float width){return core*k*line_scale(width);}
inline float dark_width(float k,float width){return core_width(k,width)+2*edge*k;}
// Connector ticks from the ring towards the nose: short bars across the line, 9 px long at 1080p (core 89%), with the
// reticle stroke widths; alpha .85 x fade x (1 - .16 i).
struct Tick {Point center,across;float opacity=0;};
constexpr float tick_length=9,tick_core_length=.89f;
inline std::array<Tick,3> ticks(Point ring_point,Point nose,float height,bool always){
    std::array<Tick,3> out{};const float scale=std::max(.75f,height/1080.f);
    const float dx=nose.x-ring_point.x,dy=nose.y-ring_point.y,distance=std::hypot(dx,dy);
    if(!std::isfinite(distance)||distance<=.001f)return out;
    const float ux=dx/distance,uy=dy/distance,start=120.f*height/2160.f*.5f*.8125f;
    const float spacing=std::clamp(distance*.03f,10*scale,18*scale);
    for(int i=0;i<3;++i){
        const float offset=start+8*scale+i*spacing,available=distance-offset-16*scale;
        if(available<=0)continue;
        const float fade=always?1.f:std::min(1.f,available/(14*scale));
        out[i]={{ring_point.x+ux*offset,ring_point.y+uy*offset},{-uy,ux},fade*(1-.16f*i)*.85f};
    }
    return out;
}
}
}
