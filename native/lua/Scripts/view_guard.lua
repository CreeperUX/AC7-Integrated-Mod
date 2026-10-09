-- Enforce the view itself; never change native input permission flags.
local M={}
local function valid(o)return o and o:IsValid()end
function M.restore()end
function M.update(pawn,active)
 if not active then return false end
 local views=pawn.CameraViewComponent
 assert(valid(views),'Camera view component unavailable')
 local current=views:GetCurrentCameraViewType()
 if current~=2 then
  -- Only redirect normal first-person/cockpit views, never replay/cinematic views.
  if current~=0 and current~=1 then return false end
  if pawn.bEnableCameraViewChange~=true then return false end
  views:SwitchToThirdPersonView()
 end
 return views:GetCurrentCameraViewType()==2
end
return M
