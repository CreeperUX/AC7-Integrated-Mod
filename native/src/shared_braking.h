#pragma once
#include <algorithm>
#include <cmath>
namespace shared_braking {
struct Model {float tau,delay,g0,g1,bias;};
// AC7 F-16C natural-flight prior. Single-aircraft fit; speed slope not established.
constexpr Model pitch{.8f,.032f,48.4f,0.f,0.f};
constexpr Model roll{.55f,.064f,171.9f,0.f,0.f};
// Frozen shared yaw prior from the same original F-15E/Typhoon identification.
constexpr Model yaw{.8f,.256f,6.4f,0.f,0.f};
inline float gain(Model m,float speed){return m.g0+m.g1*(speed-455.740317f)/177.865169f;}
// Closed form constant-input first-order rate response. No game calls/state writes.
inline float advance(Model m,float u,float speed,float dt,float& rate){
    float equilibrium=gain(m,speed)*u+m.bias;
    float decay=std::exp(-dt/m.tau);
    float angle=equilibrium*dt+(rate-equilibrium)*m.tau*(1-decay);
    rate=equilibrium+(rate-equilibrium)*decay;return angle;
}
inline float travel(Model m,float rate,float previous_input,float candidate,float speed,float horizon){
    float delay=std::min(horizon,m.delay);
    float angle=advance(m,previous_input,speed,delay,rate);
    return angle+advance(m,candidate,speed,horizon-delay,rate);
}
struct Axis {
    float delta=0;
    void reset(){delta=0;}
    float correction(Model m,float error,float rate,float previous_input,float baseline,float speed,
                     float horizon,float range,float zone,float strength,float cap,float slew,float dt){
        if(!std::isfinite(error)||!std::isfinite(rate)||!std::isfinite(previous_input)||!std::isfinite(baseline)||
           !std::isfinite(speed)||!std::isfinite(strength)||!std::isfinite(dt)||dt<=0||dt>.1){reset();return 0;}
        if(speed<130 || speed>660 || strength<=0 || std::abs(error)>=range || std::abs(rate)<1 ||
           (error*rate<=0 && std::abs(error)>zone)){reset();return 0;}
        float sign=std::copysign(1.f,rate);
        float expected=sign*travel(m,rate,previous_input,baseline,speed,horizon);
        float remaining=std::max(0.f,sign*error-zone);
        float excess=std::max(0.f,expected-remaining);
        float fraction=std::clamp(excess/std::max(1.f,std::abs(expected)+remaining),0.f,1.f);
        float fade=1-std::pow(std::abs(error)/range,2.f);
        float maximum=cap*std::clamp(strength/.2f,0.f,1.75f);
        float wanted=-sign*maximum*fade*fraction;
        // Never carry old-direction braking through a rate sign change.
        if(delta*rate>0)delta=0;
        delta+=std::clamp(wanted-delta,-slew*dt,slew*dt);
        delta=std::clamp(delta,-maximum,maximum);
        return delta;
    }
};
}
