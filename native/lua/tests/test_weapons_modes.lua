-- Offline harness for AC7Weapons missile tiers (modes.lua + main.lua) with mock UE4SS globals.
-- usage: texlua test_weapons_modes.lua <AC7Weapons Scripts dir with trailing slash>
local dir=assert(arg[1],'Scripts directory')
local real_print=print
local spec=dofile(dir..'spec.lua');local modes=dofile(dir..'modes.lua')
local n=0;for _ in pairs(spec)do n=n+1 end
-- full: the spec, plus each VeryEasy_ copy (Damage, LoadTime, HomingForesightAmount, LockonAngle, LockonRange) set
-- to the same value (AC8 patches its EASY / C.STORY rows the same way)
local full,classes,fields=modes.select(spec,'full')
local total,mirrors=0,0
for name,r in pairs(spec)do for k,v in pairs(r)do total=total+1;assert(full[name][k]==v,name..' '..k)end
 for _,b in ipairs(modes.VARIANTS)do if r[b]~=nil then mirrors=mirrors+1;assert(full[name]['VeryEasy_'..b]==r[b],name..' mirror '..b)end end end
assert(classes==n and fields==total+mirrors and mirrors==54,'full counts '..fields..' '..mirrors)
assert(full.plwp_msl_a0_C.VeryEasy_LockonRange==24000 and full.plwp_4aam_a0_C.VeryEasy_LockonRange==100000 and full.plwp_laam_a0_C.VeryEasy_LockonRange==200000,'lock ranges mirrored')
-- guidance: one field per class, the AC8 HomingForesightAmount values (AC8 source_spec, 30 weapon rows)
local g,gc,gf=modes.select(spec,'guidance')
assert(gc==30 and gf==60,'guidance counts '..gc..' '..gf)
local expected={['2aam']=.95,['4aam']=.9,['6aam']=.9,hcaa=.8,hpaa=.75,hvaa=.85,laam=.9,msl=1,qaam=1,saam=.95,sasm=.9}
for name,r in pairs(g)do
 local k=0;for key in pairs(r)do k=k+1;assert(key=='HomingForesightAmount'or key=='VeryEasy_HomingForesightAmount',name..' extra field '..key)end;assert(k==2)
 assert(r.VeryEasy_HomingForesightAmount==r.HomingForesightAmount,name..' mirror')
 local family=name:match('^plwp_(%w+)_')
 assert(math.abs(r.HomingForesightAmount-expected[family])<1e-9,name..' lead '..r.HomingForesightAmount)
end
assert(not pcall(modes.select,spec,'weapons')and not pcall(modes.select,spec,nil),'unknown modes must fail')
-- main.lua loads for both tiers outside a mission (no QAAM visual module any more)
for _,mode in ipairs({'guidance','full'})do
 local logged={}
 _G.print=function(s)logged[#logged+1]=s end
 _G.RegisterHook=function()end;_G.LoopInGameThreadAfterFrames=function(_,f)_G.tick=f end;_G.FindFirstOf=function()return nil end
 local real=dofile;_G.dofile=function(p)if p:match('settings%.lua$')then return {missile_mode=mode}end;return real(p)end
 real(dir..'main.lua');_G.dofile=real
 assert(_G.tick()==false,'tick')
 local line=table.concat(logged,' ')
 assert(line:find('missile_mode='..mode..' classes=30 fields='..(mode=='guidance'and 60 or total+mirrors),1,true),line)
 assert(not line:find('QAAM'),'no visual module')
end
-- reconcile pass against mock UE objects: wrapped (RemoteUnrealParam-like) elements are unwrapped, a broken element
-- does not stop the pass, CDO and owned instance get the field and its VeryEasy_ copy, leaving the mission restores
do
 local logged={};_G.print=function(s)logged[#logged+1]=s end
 local rules=modes.select(spec,'full').plwp_msl_a0_C
 local function weapon_obj(owner)
  local o={OwningGameObject=owner and {get=function()return owner end}}
  for k,v in pairs(rules)do if type(v)=='boolean'then o[k]=false else o[k]=0 end end
  o.IsValid=function()return true end;o.GetAddress=function()return tostring(o)end
  o.GetClass=function()return {GetFName=function()return {ToString=function()return 'plwp_msl_a0_C'end}end}end
  return o
 end
 local pawn={InputPitch=0,IsValid=function()return true end};pawn.GetAddress=function()return 'pawn'end
 local cdo,inst=weapon_obj(nil),weapon_obj(pawn)
 local ap={LockonRange=24000,IsValid=function()return true end,GetClass=function()return {GetFName=function()return {ToString=function()return 'MissileParameters'end}end}end}
 local broken=setmetatable({},{__index=function()error('broken element')end})
 pawn.PlayerWeaponActivator={IsValid=function()return true end,MainWeaponClass={IsValid=function()return true end,GetCDO=function()return cdo end},
  SpawnedWeapons={broken,{get=function()return inst end}},ActiveWeapons={},ExplosiveWeaponsShot={},GetArmedWeaponParameters=function()return ap end}
 local pc={IsValid=function()return true end,Pawn=pawn}
 local engine={IsValid=function()return true end,GameViewport={IsValid=function()return true end,World={IsValid=function()return true end,
  OwningGameInstance={IsValid=function()return true end,LocalPlayers={{PlayerController=pc}}}}}}
 local inMission=true
 _G.RegisterHook=function()end;_G.LoopInGameThreadAfterFrames=function(_,f)_G.tick=f end
 _G.FindFirstOf=function()return inMission and engine or nil end
 local real=dofile;_G.dofile=function(p)if p:match('settings%.lua$')then return {missile_mode='full'}end;return real(p)end
 real(dir..'main.lua');_G.dofile=real
 for _=1,6 do _G.tick()end   -- the pass runs every 6th frame
 assert(cdo.LockonRange==24000 and cdo.VeryEasy_LockonRange==24000 and cdo.VeryEasy_LockonAngle==160 and cdo.VeryEasy_Damage==80,'CDO and VeryEasy copies')
 assert(inst.LockonRange==24000 and inst.VeryEasy_HomingForesightAmount==1,'owned instance behind a wrapper')
 local line=table.concat(logged,' ')
 assert(line:find('PERFORMANCE default plwp_msl_a0_C changed=',1,true)and line:find('VeryEasy_LockonRange 0->24000',1,true),line)
 assert(line:find('ARMED MissileParameters LockonRange=24000',1,true),line)
 inMission=false;for _=1,6 do _G.tick()end
 assert(cdo.LockonRange==0 and cdo.VeryEasy_LockonRange==0,'stock values restored outside the mission')
end
real_print('PASS AC7Weapons reconcile: wrapped elements, broken element isolated, VeryEasy copies patched, armed lock range logged, restore')
real_print('PASS AC7Weapons tiers: full = '..total..' fields + '..mirrors..' VeryEasy copies on 30 classes, guidance = 30 HomingForesightAmount values (AC8) + copies, main.lua loads for both')
