-- captura escena de Draco: char mirror con pmd DIRECTO (draco_charram), page 2KB.
local TARGET=tonumber(os.getenv("CIDELSA_FRAME")) or 350
local DIR=(os.getenv("CIDELSA_DIR") or "C:/_PROYECTOS/Cidelsa/debug/destryer/draco").."/"
local m=manager.machine; local vis=m.devices[":cdp1869"]; local cpu=m.devices[":cdp1802"]; local scr=m.screens[":screen"]
local pageram=vis.spaces["pageram"]; local io_sp=cpu.spaces["io"]; local prog=cpu.spaces["program"]
local reg={bkg=0,cfc=0,dispoff=0,col=0,freshorz=0,cmem=0,line9=0,line16=0,dblpage=0,fresvert=0,pma=0,hma=0}
local reg_disp={}; for k,v in pairs(reg) do reg_disp[k]=v end
local f=0; local snapped=false
local charram={}; local pcbram={}; for i=0,0x7ff do charram[i]=0; pcbram[i]=0 end
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
local function qv() return cpu.state["Q"].value&1 end
TAPS={}
TAPS[#TAPS+1]=io_sp:install_write_tap(0x03,0x07,"o",function(o,d,mk)
  local n=o
  if n==3 then local x=d&0xff; reg.bkg=x&7; reg.cfc=(x>>3)&1; reg.dispoff=(x>>4)&1; reg.col=(x>>5)&3; reg.freshorz=(x>>7)&1
  else local a=rx()
    if n==5 then reg.cmem=a&1; reg.line9=(a>>3)&1; reg.line16=(a>>5)&1; reg.dblpage=(a>>6)&1; reg.fresvert=(a>>7)&1; reg.pma=(reg.cmem==1) and (a&0x7ff) or 0
    elseif n==6 then reg.pma=a&0x7ff elseif n==7 then reg.hma=a&0x7fc end end
end)
TAPS[#TAPS+1]=pageram:install_read_tap(0x000,0x7ff,"pr",function(o,d,mk)
  if not snapped then for k,v in pairs(reg) do reg_disp[k]=v end; snapped=true end end)
TAPS[#TAPS+1]=prog:install_write_tap(0xF400,0xF7FF,"c",function(off,d,mk)
  local o=off-0xF400; local cma=o&0xf; local pma
  if reg.cmem==1 then pma=(reg.dblpage==1) and reg.pma or (reg.pma&0x3ff) else pma=o end
  local pmd=pageram:read_u8(pma&0x7ff)
  local addr=((pmd<<3)|(cma&7))&0x7ff   -- DRACO: pmd directo (sin column/0xff)
  charram[addr]=d&0xff; pcbram[addr]=qv() end)
local function dh(p,t,n) local fh=assert(io.open(p,"w")); for i=0,n-1 do fh:write(string.format("%02x\n",t[i]&0xff)) end; fh:close() end
emu.register_frame_done(function()
  f=f+1
  if f~=TARGET then if f>TARGET then m:exit() end; snapped=false; return end
  local page={}; for i=0,0x7ff do page[i]=pageram:read_u8(i) end   -- 2KB
  dh(DIR.."page_ram.hex",page,0x800); dh(DIR.."char_ram.hex",charram,0x800); dh(DIR.."pcb_ram.hex",pcbram,0x800)
  local fh=assert(io.open(DIR.."regs.txt","w")); for _,k in ipairs({"bkg","cfc","dispoff","col","freshorz","line9","line16","dblpage","fresvert","hma"}) do fh:write(string.format("%s=%d\n",k,reg_disp[k])) end; fh:write("draco=1\n"); fh:close()
  local ok,pix=pcall(function() return scr:pixels() end); if ok and pix then local pf=assert(io.open(DIR.."screen.bin","wb")); pf:write(pix); pf:close() end
  print(string.format(">>> DRACO f%d DISPLAY: col=%d cfc=%d bkg=%d dbl=%d l16=%d fhz=%d fvt=%d l9=%d hma=0x%x [%dx%d]",
     f,reg_disp.col,reg_disp.cfc,reg_disp.bkg,reg_disp.dblpage,reg_disp.line16,reg_disp.freshorz,reg_disp.fresvert,reg_disp.line9,reg_disp.hma,scr.width,scr.height)); m:exit()
end)
