-- Missile rule tiers, as AC8 missile_mode: full = every changed field of the ported AC8 rules (spec.lua);
-- guidance = only the proportional-navigation lead (HomingForesightAmount), stock speed, range, damage, fuze
-- and blast otherwise.
-- AC7 WeaponBase keeps a VeryEasy_ copy of Damage, LoadTime, HomingForesightAmount, LockonAngle and LockonRange; when
-- spawning a weapon or building the armed MissileParameters from the class default, the game takes the copy instead
-- of the field for owners flagged for it (Ace7Game 0x8986A0). These copies are AC7's counterpart of AC8's EASY /
-- C.STORY DT_WeaponSettings rows, which AC8 patches in both tiers, so every chosen field is mirrored into its copy.
local M={}
M.GUIDANCE_CLASSES=30
M.VARIANTS={'Damage','LoadTime','HomingForesightAmount','LockonAngle','LockonRange'}
local function mirrored(rules)
 local out={}
 for k,v in pairs(rules)do out[k]=v end
 for _,base in ipairs(M.VARIANTS)do if out[base]~=nil then out['VeryEasy_'..base]=out[base]end end
 return out
end
function M.select(spec,mode)
 assert(mode=='full'or mode=='guidance','Unsupported missile_mode '..tostring(mode))
 local out,classes,fields={},0,0
 for name,rules in pairs(spec)do
  local chosen
  if mode=='full'then chosen=mirrored(rules)
  else local lead=rules.HomingForesightAmount;assert(type(lead)=='number','No guidance lead for '..name);chosen=mirrored({HomingForesightAmount=lead})end
  out[name]=chosen;classes=classes+1
  for _ in pairs(chosen)do fields=fields+1 end
 end
 if mode=='guidance'then assert(classes==M.GUIDANCE_CLASSES,'Guidance specification changed; validate before installation')end
 return out,classes,fields
end
return M
