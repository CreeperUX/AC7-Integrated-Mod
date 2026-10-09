-- AC7 adapter for the AC8 2.4.2 control core (AC7 0.5.x): pose/camera/metadata bridge, view context, HMD, HUD-layer reticle (hud_renderer=3).
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local function load(name)return assert(package.loadlib(dir..'ac7_mouse_aim.dll','ac7_mouseaim_'..name))end
local start,begin,frame,control,camera,release,bind,observe,health,reload=load('start'),load('begin'),load('frame'),load('control_observe'),load('camera'),load('release'),load('bind'),load('observe'),load('health'),load('reload')
local aim_camera=dofile(dir..'camera.lua')
local view_guard=dofile(dir..'view_guard.lua')
local context_native,manual_look,helmet_state,helmet_submit=load('context'),load('manual_look'),load('helmet_state'),load('helmet_submit')
local view_context=dofile(dir..'view_context.lua').new()
local helmet=dofile(dir..'helmet.lua').new(helmet_submit)
local helmet_error
local valid=function(o)return o and o:IsValid()end
local number=function(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
local function component(v,k)return v[k]end
local function log(s)print('[AC7FullControl] '..s..'\n')end
assert(start(1729,.125)==30,'AC7 full core refused: verify native log, runtime and game build')
local native_hud=dofile(dir..'native_hud.lua')
local hud_ok,hud_error=pcall(native_hud.start,dir)
if not hud_ok then log('native reticle unavailable: '..tostring(hud_error)..'; GPU overlay draws the reticle')end
local engine,gameplay,mission,owner,startup,identity,offsets,last_error
local warmup,sim,next_record,frame_count=0,0,0,0
local last_status=0
local status=assert(io.open(dir..'full-health.csv','w'))
status:write('time_s,pawn,plane,speed_mps,on,pitch,yaw,roll,target_pitch,target_yaw,input_calls,applied_calls,command_pitch,command_roll,command_yaw,camera_calls,camera_applied\n');status:flush()
local function stop(reason)
 release();aim_camera.restore();view_guard.restore();view_context:reset(reason);helmet:clear();context_native(1,0,0);if hud_ok then native_hud.hide()end;if owner then log('RELEASE '..reason)end
 owner=nil;startup=nil;identity=nil;warmup=0;sim=0;next_record=0
end
local function resolve_offsets()
 if offsets then return offsets end
 local cls=StaticFindObject('/Script/Nimbus.PlayerPlane');assert(valid(cls),'PlayerPlane class missing')
 local props={};cls:ForEachProperty(function(p)props[p:GetFName():ToString()]=p:GetOffset_Internal()end)
 offsets={assert(props.InputPitch),assert(props.InputRoll),assert(props.InputLeftYaw),assert(props.InputRightYaw)}
 return offsets
end
local function plane_identity(pawn)
 local id;pcall(function()id=pawn.PlaneTypeID end)
 if number(id)and id>=0 and id<=2147483647 and id==math.floor(id)then return id end
 -- Local learner key for a runtime class, not a claimed native aircraft ID.
 local cls=pawn:GetFullName():match('^([^ ]+)');local h=5381
 for i=1,#cls do h=(h*33+cls:byte(i))%2147483647 end
 log('class-derived model key '..h..' for '..cls);return h
end
RegisterKeyBind(Key.F10,function()reload();aim_camera.configure()end)
assert(EngineTickAvailable~=false and type(LoopInGameThreadAfterFrames)=='function','Required game-thread callback unavailable')
LoopInGameThreadAfterFrames(1,function()
 begin();frame_count=frame_count+1
 if not owner and frame_count%15~=0 then return false end
 local ok,err=pcall(function()
  if not valid(engine)then engine=FindFirstOf('GameEngine')end
  if not valid(gameplay)then gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')end
  if not valid(engine)or not valid(gameplay)then stop('engine unavailable');return end
  local viewport=engine.GameViewport;if not valid(viewport)then stop('viewport unavailable');return end
  local world=viewport.World;if not valid(world)then stop('world unavailable');return end
  local gi=world.OwningGameInstance;if not valid(gi)then stop('instance unavailable');return end
  local players=gi.LocalPlayers;if #players~=1 then stop('not single local player');return end
  local pc=players[1].PlayerController;if not valid(pc)then stop('controller unavailable');return end
  local pawn=pc.Pawn;if not valid(pawn)then stop('pawn unavailable');return end
  if not number(pawn.InputPitch)or not number(pawn.InputRoll)then stop('not player plane');return end
  local address=pawn:GetAddress();local dt=gameplay:GetWorldDeltaSeconds(pawn)
  if owner~=address then
   if startup~=address then stop('pawn changed');startup=address;warmup=0;mission=nil end
   warmup=warmup+math.max(0,math.min(.1,dt))*15
   if warmup<.5 then return end
   assert(bind(address,table.unpack(resolve_offsets()))==1,'Native input layout rejected')
   owner=address;identity=plane_identity(pawn);log('ACQUIRE '..pawn:GetFullName()..' model='..identity)
  end
  if not valid(mission)then mission=FindFirstOf('Mission')end
  local manager=pc.PlayerCameraManager;assert(valid(manager),'Camera manager unavailable')
  local target=pc:GetViewTarget()
  local view_type=pawn.CameraViewComponent:GetCurrentCameraViewType()
  local special_view=view_type~=0 and view_type~=1 and view_type~=2
  local cinematic=view_context:optional_bool(pc,'bCinematicMode',false)==true
  local input_ignored=view_context:optional_bool(pc,'IsMoveInputIgnored',true)==true
  local gated=gameplay:IsGamePaused(pawn)==true or special_view or cinematic or input_ignored or (valid(mission)and mission:IsInIGC()==true)or
   pawn.bEnableWingInput~=true or pawn.bEnableMovmentInput~=true or pawn:IsExpertControlType()~=true or valid(world.NetDriver)or
   not valid(target)or target:GetAddress()~=address or not number(dt)or dt<=0 or dt>.1
  local t=gameplay:GetRealTimeSeconds(pawn)
  local ready,reseed=view_context:update(address,pc:GetAddress(),not gated,dt,t)
  local looking=manual_look()==1
  assert(context_native(ready and 0 or 1,reseed and 1 or 0,looking and 1 or 0)==1,'View context rejected')
  gated=gated or not ready
  local r=pawn:K2_GetActorRotation();local pos=pawn:K2_GetActorLocation();local v=pawn:GetVelocity()
  local view=manager:GetCameraRotation();local loc=manager:GetCameraLocation();local fov=manager:GetFOVAngle()
  local speed=pawn:GetSpeedMps();local brake=pawn.InputBrake
  local on,tp,ty=frame(address,r.Pitch,r.Yaw,r.Roll,view.Pitch,view.Yaw,view.Roll,fov,
   (loc.X-pos.X)*10,(loc.Y-pos.Y)*10,(loc.Z-pos.Z)*10,gated and 1 or 0,0,math.max(.0001,math.min(.1,dt)))
  assert(on~=nil,'Pose rejected by native bridge')
  local view_ready=view_guard.update(pawn,on==1 and not gated)
  local hmd,hp,hy,aspect=helmet_state()
  if hmd==1 and not gated then
   local hok,herr=pcall(function()helmet:update(pawn,pos,loc,{view.Pitch,view.Yaw,view.Roll},{hp,hy},fov,aspect,t,component)end)
   if not hok then helmet:clear();helmet_submit(-1,0,0,0);if tostring(herr)~=helmet_error then helmet_error=tostring(herr);log('HMD unavailable: '..helmet_error)end end
  else helmet:clear()end
  if not gated then
   local environment=(looking or pawn.bIsInCloud==true or pawn.bIsInSand==true or pawn.bIsInIce==true)and 1 or 0
   assert(control(address,speed,0,0,brake,identity,environment)==1,'Control metadata rejected')
   sim=sim+dt
   if sim>=next_record then
    next_record=sim+1/30
    -- Shared recorder contract: cm, cm/s. AC7 actor space uses 10 units/metre.
    observe(address,pos.X*10,pos.Y*10,pos.Z*10,v.X*10,v.Y*10,v.Z*10,pawn.InputThrottle,brake,identity,dt,sim,environment)
   end
  end
  local desired=aim_camera.update(pawn,pc,r,component,on,tp,ty,math.max(0,math.min(.1,dt)))
  if desired and not gated and view_ready then
   assert(camera(manager:GetAddress(),address,desired.pitch,desired.yaw,desired.roll,pos.X,pos.Y,pos.Z)==1,'Camera command rejected')
  else camera(0,0,0,0,0,0,0,0)end
  if hud_ok then if gated then native_hud.hide()else native_hud.update(pc,pawn)end end
  if t-last_status>.1 or t<last_status then
   last_status=t;local calls,applied,cp,cr,cy,cam_calls,cam_applied=health()
   status:write(string.format('%.4f,%.0f,%d,%.3f,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.0f,%.0f,%.5f,%.5f,%.5f,%.0f,%.0f\n',t,address,identity,speed,on,r.Pitch,r.Yaw,r.Roll,tp,ty,calls,applied,cp,cr,cy,cam_calls,cam_applied));status:flush()
  end
 end)
 if not ok then stop('frame error');if tostring(err)~=last_error then last_error=tostring(err);log('ERROR '..last_error)end end
 return false
end)
log('AC7 0.6.0-beta.1 (AC8 2.4.2 core); WAR exact flight-engine controller, reticle on the GPU overlay at native resolution (hud_renderer=1; 3 = inside the game HUD), F4 PEACE/WAR, F2 helmet target priority, F3 native/far camera, F8 toggle, F9 recenter, C free look')
