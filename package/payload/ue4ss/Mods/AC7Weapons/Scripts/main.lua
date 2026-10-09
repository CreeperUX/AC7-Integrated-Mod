local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local patch=dofile(dir..'patch.lua')
local settings=dofile(dir..'settings.lua')
-- Tier written by the installer from features.ini: guidance (lead only) or full (all AC8 rules).
local rules,classes,fields=dofile(dir..'modes.lua').select(dofile(dir..'spec.lua'),settings.missile_mode)
local defaults,reported={},{ }
local ticks=0
-- Array elements and some returns arrive as RemoteUnrealParam: unwrap them; never let one bad element abort a pass.
local function deref(x)
 if type(x)~='userdata'and type(x)~='table'then return x end
 if pcall(function()return x:IsValid()end)then return x end   -- a UObject: use as is
 local ok,v=pcall(function()return x:get()end);if ok and v~=nil then return v end
 return x
end
local function valid(o)o=deref(o);if not o then return false end;local ok,r=pcall(function()return o:IsValid()end);return ok and r==true end
local function same(a,b)a,b=deref(a),deref(b);return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function log(key,s)if not reported[key]then reported[key]=true;print('[AC7Weapons] '..s..'\n')end end
local function attempt(key,fn)local ok,e=pcall(fn);if not ok then log('error:'..key,'ERROR '..key..' '..tostring(e))end end
local function leaf(o)return o:GetClass():GetFName():ToString()end
local function context()
 local e=FindFirstOf('GameEngine');if not valid(e)or not valid(e.GameViewport)then return end
 local w=e.GameViewport.World;if not valid(w)or valid(w.NetDriver)then return end
 local gi=w.OwningGameInstance;if not valid(gi)or #gi.LocalPlayers~=1 then return end
 local pc=gi.LocalPlayers[1].PlayerController;if not valid(pc)then return end
 local p=pc.Pawn;if not valid(p)then return end
 local ok,result=pcall(function()return type(p.InputPitch)=='number'and valid(p.PlayerWeaponActivator)end)
 if ok and result then return p end
end
local function range_note(before,after)
 local parts={}
 for _,k in ipairs({'LockonRange','VeryEasy_LockonRange','LockonAngle','VeryEasy_LockonAngle','HomingForesightAmount','VeryEasy_HomingForesightAmount'})do
  if after[k]~=nil and before[k]~=nil then parts[#parts+1]=string.format('%s %.6g->%.6g',k,before[k],after[k])end
 end
 return table.concat(parts,' ')
end
local function performance(o,kind)
 local name=leaf(o);local family=name:match('^plwp_(%w+)_[%w]+_C$')
 local spec=rules[name]or(family and rules['plwp_'..family..'_a0_C']);if not spec then return end
 local changed,before=patch.apply(o,spec)
 if kind=='default'and changed>0 then
  local address=o:GetAddress();if not defaults[address]then defaults[address]={object=o,original=before}end
 end
 if changed>0 then log(kind..name,'PERFORMANCE '..kind..' '..name..' changed='..changed..' readback=ok '..range_note(before,spec))end
end
-- Diagnostic: lock range of the armed weapon parameters (rebuilt by the game from the class default), logged on change.
local armed_seen={}
local function armed(a)
 local ok,ap=pcall(function()return a:GetArmedWeaponParameters()end);ap=ok and deref(ap)or nil
 if not valid(ap)then return end
 local okr,range=pcall(function()return ap.LockonRange end)
 if not(okr and type(range)=='number')then   -- the value may sit in a struct member of the parameters object
  pcall(function()ap:GetClass():ForEachProperty(function(prop)
   if type(range)~='number'then local n=prop:GetFName():ToString();local okm,v=pcall(function()return ap[n].LockonRange end);if okm and type(v)=='number'then okr,range=true,v end end
  end)end)
 end
 if okr and type(range)=='number'then
  local key=leaf(ap)..':'..string.format('%.6g',range)
  if not armed_seen[key]then armed_seen[key]=true;print('[AC7Weapons] ARMED '..leaf(ap)..' LockonRange='..string.format('%.6g',range)..'\n')end
 end
end
local function weapon(o,p)
 o=deref(o);if not valid(o)or not same(o.OwningGameObject,p)then return end
 performance(o,'owned')
end
-- Blueprint initialization can precede ownership assignment. The bounded tick
-- reconciliation below covers this, pooled actors, and missed native callbacks.
attempt('initialization hook',function()
 RegisterHook('/Script/Nimbus.WeaponBase:OnInitialized',function()end,function(param)
  attempt('initialized weapon',function()
   local p=context();if not p then return end
   local o=deref(param);if not valid(o)or not same(o.OwningGameObject,p)then return end
   weapon(o,p)
  end)
 end)
end)
LoopInGameThreadAfterFrames(1,function()
 ticks=ticks+1;if ticks%6~=0 then return false end
 attempt('reconcile',function()
  local p=context()
  if not p then
   for address,state in pairs(defaults)do
    if valid(state.object)then patch.restore(state.object,state.original)end
    defaults[address]=nil
   end
   return
  end
  local a=deref(p.PlayerWeaponActivator)
  for _,field in ipairs({'MainWeaponClass','SpecialWeaponClass'})do
   attempt(field,function()local c=deref(a[field]);if valid(c)then performance(c:GetCDO(),'default')end end)
  end
  for _,field in ipairs({'SpawnedWeapons','ActiveWeapons','ExplosiveWeaponsShot'})do
   attempt(field,function()
    local list=a[field];assert(#list<=512,'Unexpected owned weapon count')
    for i=1,#list do
     local o=deref(list[i])
     if valid(o)then attempt('owned '..leaf(o),function()weapon(o,p)end)end
    end
   end)
  end
  attempt('armed',function()armed(a)end)
 end)
 return false
end)
log('start','missile_mode='..settings.missile_mode..' classes='..classes..' fields='..fields..'; stock values restored outside missions; single-player only')
