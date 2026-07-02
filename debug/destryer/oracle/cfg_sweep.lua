-- barrido RÁPIDO de config de display (col/cfc/bkg/line16/dblpage) por frame.
-- Sin tap de char (rápido). Config robusta: snapshot en OUT3 / OUT5-cmem0.
local m=manager.machine; local cpu=m.devices[":cdp1802"]; local io_sp=cpu.spaces["io"]
local reg={bkg=0,cfc=0,col=0,freshorz=0,line9=0,line16=0,dblpage=0,fresvert=0,cmem=0,dispoff=0}
local rd={}; for k,v in pairs(reg) do rd[k]=v end
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
local function snap() for k,v in pairs(reg) do rd[k]=v end end
TAPS={}
TAPS[1]=io_sp:install_write_tap(0x03,0x07,"o",function(o,d,mk)
  if o==3 then local x=d&0xff; reg.bkg=x&7; reg.cfc=(x>>3)&1; reg.dispoff=(x>>4)&1; reg.col=(x>>5)&3; reg.freshorz=(x>>7)&1; snap()
  elseif o==5 then local a=rx(); reg.cmem=a&1; reg.line9=(a>>3)&1; reg.line16=(a>>5)&1; reg.dblpage=(a>>6)&1; reg.fresvert=(a>>7)&1; if reg.cmem==0 then snap() end end
end)
local f=0; local seen={}
emu.register_frame_done(function()
  f=f+1
  local k=string.format("col=%d cfc=%d bkg=%d dbl=%d l16=%d fhz=%d fvt=%d l9=%d dispoff=%d",rd.col,rd.cfc,rd.bkg,rd.dblpage,rd.line16,rd.freshorz,rd.fresvert,rd.line9,rd.dispoff)
  if not seen[k] then seen[k]=f; print(string.format("  f%4d: %s",f,k)) end
  if f>=3000 then m:exit() end
end)
