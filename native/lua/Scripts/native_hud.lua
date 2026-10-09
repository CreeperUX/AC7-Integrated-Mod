-- AC7 native reticle: the AC8 2.4.1 native HUD (ring, HMD bracket ring, reference gun cross, connector ticks) drawn by
-- the game's own UMG inside the flight HUD (NimbusHUD.HudWidget = AceMainFlightHUD_C, root CanvasPanel BaseCanvas). AC7
-- renders that widget into a 1920x1080 render target (HudPostProcessConverter.DrawSize), adds its glow and composites it
-- additively over the frame (ac7/re/hudprobe, 2026-10-08), so: units are 1920x1080 on any screen, black outlines are
-- invisible (core strokes only), and colours are linear (AC8 sRGB cyan 88,203,225 -> 0.098,0.597,0.753, user-chosen).
-- AC7's engine has no ImportFileAsTexture2D, so every element is assembled from solid UMG Image bars with the geometry of
-- the AC8 textures (lua/make_reticles.py, 128-unit texture space): 4-unit core, ring centre radius 48 (measured on the
-- shipped ring.png), gun-cross arms 8..28, HMD brackets at r 58.5 +-14 deg. Each shape is a child CanvasPanel moved as
-- one unit with SetRenderTranslation.
local M={};local mode,gate,query,report,viewport,ui,nose,look
local imageClass,panelClass,slate;local state,failed;local budget=80;local logged={}
local motion={translations=0,since=nil}
local CYAN={R=.0976,G=.5972,B=.7529};local DARK={R=0,G=0,B=0};local DARK_ALPHA=.9
local OUTLINE=false   -- additive HUD layer: a dark outline pass would draw nothing
local function valid(o)return o and o:IsValid()end
local function log(s)print('[AC7NativeUI] '..s..'\n')end
local function once(k,s)if budget>0 and not logged[k]then logged[k]=true;budget=budget-1;log(s)end end
local lastStatus
local function status(s)if s~=lastStatus then lastStatus=s;once(s,'STATE '..s)end end

-- ---- geometry (128-unit texture space, origin at the texture centre, +y down) ----
local SEGMENTS=40
local function bar(x0,y0,x1,y1,cap)   -- straight stroke; cap*width extra length in total stands in for the round caps
 local dx,dy=x1-x0,y1-y0;return {x=(x0+x1)/2,y=(y0+y1)/2,len=math.sqrt(dx*dx+dy*dy),ang=math.deg(math.atan(dy,dx)),cap=cap}
end
local function pol(r,a)return r*math.cos(math.rad(a)),r*math.sin(math.rad(a))end
local function ring(r,out)
 local step=360/SEGMENTS;local chord=2*r*math.sin(math.rad(step/2))
 for i=0,SEGMENTS-1 do local a=(i+.5)*step;local x,y=pol(r,a);out[#out+1]={x=x,y=y,len=chord,ang=a+90,cap=.35}end
 return out
end
local SHAPES={}
SHAPES.ring=ring(48,{})
SHAPES.hmd=ring(47.75,{})
for _,a in ipairs({45,135,225,315})do
 local x0,y0=pol(58.5,a-14);local x1,y1=pol(58.5,a);local x2,y2=pol(58.5,a+14)
 SHAPES.hmd[#SHAPES.hmd+1]=bar(x0,y0,x1,y1,.5);SHAPES.hmd[#SHAPES.hmd+1]=bar(x1,y1,x2,y2,.5)
end
SHAPES.bore={bar(-28,0,-8,0,.5),bar(8,0,28,0,.5),bar(0,-28,0,-8,.5),bar(0,8,0,28,.5)}

local function initialize()
 if valid(imageClass)and valid(panelClass)and valid(slate)then return end
 imageClass=StaticFindObject('/Script/UMG.Image');panelClass=StaticFindObject('/Script/UMG.CanvasPanel')
 local c=StaticFindObject('/Script/UMG.SlateBlueprintLibrary');slate=valid(c)and c:GetCDO()
 assert(valid(imageClass)and valid(panelClass)and valid(slate),'Native UI classes unavailable')
end
local function place(slot,x,y,w,h,z)
 slot:SetAutoSize(false);slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}});slot:SetAlignment({X=.5,Y=.5})
 slot:SetPosition({X=x,Y=y});slot:SetSize({X=w,Y=h});if z then slot:SetZOrder(z)end
end
local function image(group,color,alpha,x,y,w,h,ang,z)
 local o=StaticConstructObject(imageClass,group);assert(valid(o),'Native image construction failed')
 local slot=group:AddChildToCanvas(o);assert(valid(slot),'UI attachment failed');place(slot,x,y,w,h,z)
 o:SetColorAndOpacity({R=color.R,G=color.G,B=color.B,A=alpha});if ang~=0 then o:SetRenderAngle(ang)end;o:SetVisibility(3)
 return o
end
-- A shape group: dark outline pass under the cyan core pass, k = slate units per texture unit.
local function build(parent,key,bars,k,size,z)
 local g=StaticConstructObject(panelClass,parent);assert(valid(g),'Native group construction failed')
 local slot=parent:AddChildToCanvas(g);assert(valid(slot),'UI group attachment failed');place(slot,0,0,size,size,z)
 local item={group=g,address=g:GetAddress(),images={},alpha=1}
 for pass=OUTLINE and 1 or 2,2 do local dark=pass==1;local w=dark and 8 or 4
  for _,b in ipairs(bars)do
   local len=b.len+(b.cap or 0)*w
   item.images[#item.images+1]={o=image(g,dark and DARK or CYAN,dark and DARK_ALPHA or 1,b.x*k,b.y*k,len*k,w*k,b.ang,pass),dark=dark}
  end
 end
 g:SetVisibility(2);item.visible=false;state.groups[key]=item;return item
end
local function tick(parent,key,len,thick,z)
 local g=StaticConstructObject(panelClass,parent);assert(valid(g),'Native tick construction failed')
 local slot=parent:AddChildToCanvas(g);assert(valid(slot),'UI tick attachment failed');place(slot,0,0,len,len,z)
 local item={group=g,address=g:GetAddress(),images={},alpha=1}
 if OUTLINE then item.images[#item.images+1]={o=image(g,DARK,DARK_ALPHA,0,0,len,thick,0,1),dark=true}end
 item.images[#item.images+1]={o=image(g,CYAN,1,0,0,len*.89,thick*.375,0,2),dark=false}
 g:SetVisibility(2);item.visible=false;state.groups[key]=item;return item
end
local function show(item,tx,ty,alpha,angle)
 item.touched=true
 if item.tx~=tx or item.ty~=ty then item.group:SetRenderTranslation({X=tx,Y=ty});item.tx=tx;item.ty=ty;motion.translations=motion.translations+1 end
 if angle and item.angle~=angle then item.group:SetRenderAngle(angle);item.angle=angle end
 if item.alpha~=alpha then
  for _,i in ipairs(item.images)do local c=i.dark and DARK or CYAN;i.o:SetColorAndOpacity({R=c.R,G=c.G,B=c.B,A=(i.dark and DARK_ALPHA or 1)*alpha})end
  item.alpha=alpha
 end
 if not item.visible then item.group:SetVisibility(3);item.visible=true end
end
local function sweep()
 for _,item in pairs(state.groups)do if not item.touched and item.visible and valid(item.group)then item.group:SetVisibility(2);item.visible=false end;item.touched=false end
end
local function destroy()
 if not state then return end
 for _,item in pairs(state.groups)do if valid(item.group)then pcall(function()item.group:RemoveFromParent()end)end end
 state=nil
end
local function local_size(p)
 local ok,a,b=pcall(function()return slate:GetLocalSize(p:GetCachedGeometry())end)
 if not ok then return end;if type(a)=='table'then a,b=a.X,a.Y end
 if type(a)=='number'and type(b)=='number'and a>=320 and b>=200 then return a,b end
end

-- Parent canvas: the flight HUD widget's root CanvasPanel; its layout space is the converter's draw size (1920x1080).
M.find_parent=function(controller)
 local hud=controller:GetHUD();if not valid(hud)then return end
 local widget=hud.HudWidget;if not valid(widget)then return end
 local root=widget.WidgetTree.RootWidget;if not valid(root)or not root:IsA(panelClass)then return end
 local w,h=1920,1080
 pcall(function()local d=hud.HudPostProcessConverter.DrawSize;if d.X>=320 and d.Y>=200 then w,h=d.X,d.Y end end)
 return root,w,h
end

function M.start(dir)
 local function api(n)return assert(package.loadlib(dir..'ac7_mouse_aim.dll','ac7_mouseaim_canvas_'..n))end
 mode=api('mode');gate=api('gate');query=api('ring');report=api('report');viewport=api('viewport');ui=api('ui');nose=api('nose')
 local okLook,lookApi=pcall(api,'look');look=okLook and lookApi or nil
 log('HUD-layer reticle available for hud_renderer=3 (UMG bars, AC8 2.4.1 geometry): ring, reference gun cross (hud_boresight, Alt+F7), HMD bracket ring, connector ticks; panel/notifications use the on-demand GPU overlay')
end
function M.hide()
 if not state then return end
 pcall(function()for _,item in pairs(state.groups)do item.touched=false end;sweep()end)
end
function M.update(controller,pawn)
 if not mode or (mode()~=2 and mode()~=3) or failed then return end
 local ok,err=pcall(function()
  initialize()
  local vw,vh,now=viewport();if not vw or vw<320 or not vh or vh<200 then return end
  local parent,pw,ph=M.find_parent(controller)
  if not valid(parent)then status('no-canvas');report(-2,0);return end
  if not pw then pw,ph=local_size(parent)end
  if not pw then status('no-geometry');return end
  local ringSize=120*ph/2160;local k=ringSize/128
  if state and (state.parent~=parent:GetAddress() or math.abs(state.ph-ph)>.5 or math.abs(state.pw-pw)>.5)then destroy()end
  if not state then
   state={parent=parent:GetAddress(),pw=pw,ph=ph,groups={}}
   build(parent,'ring',SHAPES.ring,k,ringSize,10010);build(parent,'hmd',SHAPES.hmd,k,ringSize,10011)
   build(parent,'look',SHAPES.hmd,k,ringSize,10012);build(parent,'bore',SHAPES.bore,k,ringSize,10013)
   local scale=math.max(.75,vh/1080);local unit=ph/vh
   for i=0,2 do tick(parent,'tick'..i,9*scale*unit,3.5*scale*unit,10009)end
   log(string.format('ATTACHED parent=%s size=%.0fx%.0f groups=7 bars=%d',parent:GetFullName(),pw,ph,(OUTLINE and 2 or 1)*(#SHAPES.ring+#SHAPES.hmd*2+#SHAPES.bore)))
  end
  local allowed,reason=gate();if allowed~=1 then sweep();status('gate '..tostring(reason));return end
  local values={ui()};if #values<16 then sweep();status('UI bridge unavailable');return end
  local hmd,opacity,connector,always=values[2],values[14],values[15],values[16]
  local freelook=values[17]==1;local boresight=values[18]~=0
  local unit=ph/vh;local alpha=math.max(.85,opacity)
  local function tx(px)return (px/vw-.5)*pw end;local function ty(py)return (py/vh-.5)*ph end
  local function onscreen(px,py,margin)return type(px)=='number'and type(py)=='number'and px>=margin and px<=vw-margin and py>=margin and py<=vh-margin end
  local on,x,y,radius,thickness,time=query(pawn:GetAddress(),vw,vh)
  local good,nx,ny=nose(pawn:GetAddress(),vw,vh)
  -- Reference gun cross: where the nose and guns point, on the ring's 500 m sphere; drawn on its own so it stays
  -- visible in C free look and while the ring is off-screen.
  if boresight and good==1 and onscreen(nx,ny,4)then show(state.groups.bore,tx(nx),ty(ny),alpha)end
  -- HMD: the bracketed ring marks where the target-switch key picks; in C free look that is the view direction.
  if hmd==1 and freelook and look then
   local lk,lx,ly=look(pawn:GetAddress(),vw,vh)
   if lk==1 and onscreen(lx,ly,8)then show(state.groups.look,tx(lx),ty(ly),alpha)end
  end
  if on==1 then
   show(state.groups[(hmd==1 and not freelook)and'hmd'or'ring'],tx(x),ty(y),alpha)
   if connector==1 and good==1 then
    local dx,dy=nx-x,ny-y;local distance=math.sqrt(dx*dx+dy*dy)
    if distance>.001 then
     local ux,uy=dx/distance,dy/distance;local rs=ringSize/unit*.5*.8125;local scale=math.max(.75,vh/1080);local spacing=math.max(10*scale,math.min(18*scale,distance*.03))
     for i=0,2 do local offset=rs+8*scale+i*spacing;local available=distance-offset-16*scale
      if available>0 then local a=(always==1 and 1 or math.min(1,available/(14*scale)))*(1-.16*i)
       show(state.groups['tick'..i],tx(x+ux*offset),ty(y+uy*offset),a*.85,math.deg(math.atan(uy,ux))+90)
      end
     end
    end
   end
   report(24,time);status('tracking native ring')
   if not motion.since then motion.since=now end
   if now-motion.since>=10000 then log('MOTION render_translation_calls='..motion.translations..' (not display FPS)');motion.since=now;motion.translations=0 end
  else status('projection '..tostring(on))end
  sweep()
 end)
 if not ok then
  pcall(destroy);failed=true;report(-1,0);log('DISABLED '..tostring(err)..'; GPU overlay reticle takes over; flight unaffected')
 end
end
return M
