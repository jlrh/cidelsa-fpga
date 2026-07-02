local m=manager.machine; local cpu=m.devices[":cdp1802"]; local io_sp=cpu.spaces["io"]; local scr=m.screens[":screen"]
local reg={dblpage=0,line9=0,line16=0,freshorz=0,fresvert=0,col=0,cfc=0,cmem=0}
local f=0; local seen={}
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
TAPS={}
TAPS[1]=io_sp:install_write_tap(0x03,0x07,"cfg",function(o,d,mk)
  if o==3 then reg.cfc=(d>>3)&1; reg.col=(d>>5)&3; reg.freshorz=(d>>7)&1
  elseif o==5 then local a=rx(); reg.cmem=a&1; reg.line9=(a>>3)&1; reg.line16=(a>>5)&1; reg.dblpage=(a>>6)&1; reg.fresvert=(a>>7)&1 end
end)
emu.register_frame_done(function()
  f=f+1
  local key=string.format("dbl=%d l9=%d l16=%d fhz=%d fvt=%d col=%d cfc=%d",reg.dblpage,reg.line9,reg.line16,reg.freshorz,reg.fresvert,reg.col,reg.cfc)
  if not seen[key] then seen[key]=f; print(string.format("frame %4d: %s",f,key)) end
  if f>=1500 then m:exit() end
end)
