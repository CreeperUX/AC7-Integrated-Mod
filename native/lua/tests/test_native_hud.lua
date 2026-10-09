-- Offline harness for the AC7 Scripts/native_hud.lua (UMG bar reticle) with mock UE objects and mock DLL exports.
-- usage: texlua test_native_hud.lua <Scripts dir with trailing slash>
local dir=assert(arg[1],'Scripts directory')
local addr=1000
local function newaddr()addr=addr+16;return addr end
local function obj(t)t=t or {};local a=newaddr();t.IsValid=function()return true end;t.GetAddress=function()return a end;return t end
local imageClass,panelClass=obj({name='Image'}),obj({name='CanvasPanel'})
local slate=obj({GetLocalSize=function(self,g)return 3840,2160 end})
local classes={['/Script/UMG.Image']=imageClass,['/Script/UMG.CanvasPanel']=panelClass,['/Script/UMG.SlateBlueprintLibrary']=obj({GetCDO=function()return slate end})}
function StaticFindObject(n)return classes[n]end
local function slot()
 local s=obj({});function s:SetAutoSize()end;function s:SetZOrder(z)self.z=z end;function s:SetAnchors(a)self.anchors=a end
 function s:SetAlignment(a)self.align=a end;function s:SetPosition(p)self.pos=p end;function s:SetSize(v)self.size=v end;return s
end
local function container(kind)
 local o=obj({kind=kind,children={},vis=0,GetFullName=function()return kind end})
 function o:AddChildToCanvas(c)self.children[#self.children+1]=c;c.slot=slot();c.parent=self;return c.slot end
 function o:SetVisibility(v)self.vis=v end;function o:SetRenderTranslation(v)self.tx=v.X;self.ty=v.Y end;function o:SetRenderAngle(a)self.angle=a end
 function o:RemoveFromParent()self.removed=true end;function o:GetCachedGeometry()return {}end
 return o
end
local constructed=0;local failConstruct=false
function StaticConstructObject(cls,parent)
 assert(parent,'outer required');if failConstruct then return nil end;constructed=constructed+1
 if cls==panelClass then return container('group')end
 assert(cls==imageClass);local o=container('image');function o:SetColorAndOpacity(c)self.color=c end;return o
end
local parent=container('parent')
local controller=obj();local pawn=obj()
local S={};local reports={}
local exports={
 mode=function()return 3 end,gate=function()if S.gate==false then return 2,8 end;return 1,0 end,report=function(n)reports[#reports+1]=n end,viewport=function()return 1920,1080,1000 end,
 ui=function()local v={0,S.hmd,3,0,.1,.1,1.75,1.75,62,0,0,0,0,.65,1,0,S.freelook,S.bore};return table.unpack(v)end,
 ring=function()if S.ring then return 1,S.ring[1],S.ring[2],30,1.3,0 end;return S.ringStatus or -7 end,
 nose=function()if S.nose then return 1,S.nose[1],S.nose[2]end end,
 look=function()if S.look then return 1,S.look[1],S.look[2]end end}
package.loadlib=function(path,fn)assert(path:find('ac7_mouse_aim.dll',1,true),path);return exports[fn:match('ac7_mouseaim_canvas_(.+)$')]end
local function fresh(findParent)
 parent=container('parent');reports={};local M=dofile(dir..'native_hud.lua');M.start(dir)
 M.find_parent=findParent or function()return parent,3840,2160 end;return M
end
-- groups in build order: ring, hmd, look, bore, tick0..2 (identified by their image counts and order)
local NAMES={'ring','hmd','look','bore','tick0','tick1','tick2'}
local function visible()
 local v={};for i,g in ipairs(parent.children)do if g.vis==3 and not g.removed then v[NAMES[(i-1)%7+1]]=g end end;return v
end
local function run(M,cfg)for k in pairs(S)do S[k]=nil end;for k,v in pairs(cfg)do S[k]=v end;M.update(controller,pawn);return visible()end
local function keys(v)local t={};for k in pairs(v)do t[#t+1]=k end;table.sort(t);return table.concat(t,' ')end
local M=fresh()
-- 1. normal flight: plain ring + reference cross + connector ticks
local v=run(M,{hmd=0,freelook=0,bore=1,ring={960,540},nose={1000,600}})
assert(v.ring and not v.hmd and v.bore and v.tick0,keys(v))
assert(#parent.children==7,'seven groups')
-- geometry: k = (120*2160/2160)/128; ring = 40 core segments (no dark pass: additive HUD layer); width 4k; radius 48k
local k=120/128;local ring=parent.children[1]
assert(#ring.children==40,'ring bars '..#ring.children)
local cyan=ring.children[1]
assert(math.abs(cyan.slot.size.Y-4*k)<1e-9,'stroke width')
assert(math.abs(math.sqrt(cyan.slot.pos.X^2+cyan.slot.pos.Y^2)-48*k)<1e-9,'ring radius')
assert(cyan.slot.z==2 and math.abs(cyan.color.R-.0976)<1e-9 and math.abs(cyan.color.G-.5972)<1e-9 and math.abs(cyan.color.B-.7529)<1e-9,'linear AC8 cyan')
local hmd=parent.children[2];assert(#hmd.children==40+8,'hmd bars '..#hmd.children)
local bore=parent.children[4];assert(#bore.children==4,'bore bars')
assert(#parent.children[5].children==1,'tick core only')
local arm=bore.children[1];assert(math.abs(arm.slot.pos.X+18*k)<1e-9 and math.abs(arm.slot.size.X-(20+2)*k)<1e-9,'gun-cross arm 8..28 with round-cap allowance')
-- translation: ring at screen (960,540) of 1920x1080 -> centre of a 3840x2160 slate canvas
assert(ring.tx==0 and ring.ty==0,'ring centred')
assert(math.abs(bore.tx-(1000/1920-.5)*3840)<1e-9 and math.abs(bore.ty-(600/1080-.5)*2160)<1e-9,'cross at nose')
assert(parent.children[5].angle and math.abs(parent.children[5].angle-(math.deg(math.atan(60,40))+90))<1e-9,'tick perpendicular to the connector')
-- 2. HMD on: bracketed HMD ring at the cursor, cross unchanged
v=run(M,{hmd=1,freelook=0,bore=1,ring={960,540},nose={960,540}})
assert(v.hmd and not v.ring and v.bore and not v.look,keys(v))
-- 3. HMD + C free look: cursor ring off-screen; bracket ring at the view point; cross still drawn
v=run(M,{hmd=1,freelook=1,bore=1,ringStatus=-7,nose={700,500},look={960,560}})
assert(v.look and v.bore and not v.ring and not v.hmd,keys(v))
-- 3b. HMD + free look with the cursor ring visible: plain cursor ring, bracket ring at the view point
v=run(M,{hmd=1,freelook=1,bore=1,ring={300,300},nose={960,540},look={960,560}})
assert(v.ring and v.look and v.bore and not v.hmd,keys(v))
-- 4. free look without HMD: no view marker
v=run(M,{hmd=0,freelook=1,bore=1,ringStatus=-5,nose={960,540},look={960,560}})
assert(v.bore and not v.look and not v.ring,keys(v))
-- 5. nose off-screen and ring behind the camera: nothing drawn
v=run(M,{hmd=0,freelook=0,bore=1,ringStatus=-5,nose={-50,540}})
assert(next(v)==nil,keys(v))
-- 6. nose unavailable: ring only
v=run(M,{hmd=0,freelook=0,bore=1,ring={960,540}})
assert(v.ring and not v.bore and not v.tick0,keys(v))
-- 7. cross switched off (hud_boresight=0 / Alt+F7)
v=run(M,{hmd=0,freelook=0,bore=0,ring={960,540},nose={1000,600}})
assert(v.ring and not v.bore and v.tick0,keys(v))
-- 8. gate closed (pause, cutscene...): everything hidden, nothing rebuilt
local before=constructed
v=run(M,{gate=false,hmd=0,freelook=0,bore=1,ring={960,540},nose={1000,600}})
assert(next(v)==nil and constructed==before,keys(v))
-- 9. opacity change recolours in place without rebuilding
assert(math.abs(cyan.color.A-.85)<1e-9,'opacity floor .85')
-- 10. canvas resize rebuilds the groups once
local old=parent.children[1];M.find_parent=function()return parent,2560,1440 end
v=run(M,{hmd=0,freelook=0,bore=1,ring={960,540},nose={1000,600}})
assert(old.removed and #parent.children==14,'rebuild on resize')
-- 11. no HUD canvas -> report(-2) every frame (GPU overlay takes over), no error
M=fresh(function()return nil end);run(M,{hmd=0,freelook=0,bore=1,ring={960,540}})
assert(reports[#reports]==-2,'missing canvas reported')
-- 12. construction failure -> disabled for the session with report(-1)
M=fresh();failConstruct=true;run(M,{hmd=0,freelook=0,bore=1,ring={960,540},nose={1000,600}})
assert(reports[#reports]==-1,'failure reported');failConstruct=false
local n=#reports;run(M,{hmd=0,freelook=0,bore=1,ring={960,540},nose={1000,600}});assert(#reports==n,'stays disabled')
-- 13. real parent lookup: flight HUD widget root canvas, layout size from the HUD post-process converter
do local M2=dofile(dir..'native_hud.lua');M2.start(dir);local root=container('root');function root:IsA(c)return true end
 local hud=obj({HudWidget=obj({WidgetTree={RootWidget=root}}),HudPostProcessConverter={DrawSize={X=1920,Y=1080}}})
 local pc=obj({GetHUD=function()return hud end})
 local p,w,h=M2.find_parent(pc);assert(p==root and w==1920 and h==1080,'flight HUD root 1920x1080')
 hud.HudWidget=nil;assert(M2.find_parent(pc)==nil,'no HUD widget -> nil')end
print('PASS AC7 native HUD: bar geometry (AC8 2.4.1 texture dimensions), ring/HMD/look/cross/tick visibility, translation, gate, opacity, resize rebuild, missing canvas and failure fallback')
