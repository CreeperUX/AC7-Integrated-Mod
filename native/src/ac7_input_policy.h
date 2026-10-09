#pragma once
#include "custom_keys.h"
// AC7 and AC8 saves both bind W/S to pitch, A/D roll, Q/E yaw and Shift/Ctrl to speed (verified by Codex on the
// user's saves); the bindings themselves come from custom_keys (config [keybindings], same defaults).
// manual_ws_pitch=0 supports a user who deliberately returns the pitch keys to throttle.
struct Ac7KeyboardInput { unsigned mask; float pitch,roll,yaw; };   // mod convention: +pull, +right roll, +right yaw
template<class Held> Ac7KeyboardInput ac7_keyboard_input(uint64_t keys,Held held,bool ws_pitch=true){
 using A=custom_keys::Action;auto k=[&](A a){return custom_keys::down(keys,a,held);};
 const bool up=ws_pitch&&k(A::PitchUp),down=ws_pitch&&k(A::PitchDown);
 const bool left=k(A::RollLeft),right=k(A::RollRight),yl=k(A::YawLeft),yr=k(A::YawRight);
 return {(up||down?1u:0u)|(yl||yr?2u:0u)|(up||down||left||right?4u:0u),
         float(up)-float(down),float(right)-float(left),float(yr)-float(yl)};
}
struct Ac7AxisInput { float pitch,roll,left_yaw,right_yaw; };
inline Ac7AxisInput ac7_select_input(Ac7AxisInput native,Ac7AxisInput automatic,
 const Ac7KeyboardInput& key,bool active,float pitch_sign,float roll_sign,float yaw_sign){
 if(!active)return native;
 // AC7's native axes contain keyboard PLUS mouse deltas (which can exceed 1).
 // A manual-axis lease must select keyboard-only input, never that mixed value.
 if(key.mask&1)automatic.pitch=key.pitch*pitch_sign;
 if(key.mask&4)automatic.roll=key.roll*roll_sign;
 if(key.mask&2){const float y=key.yaw*yaw_sign;automatic.left_yaw=y<0?-y:0;automatic.right_yaw=y>0?y:0;}
 return automatic;
}
