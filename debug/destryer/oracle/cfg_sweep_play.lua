-- barrido de config DURANTE gameplay (inyecta moneda+start). Config por render (pageram).
local m=manager.machine; local vis=m.devices[":cdp1869"]; local cpu=m.devices[":cdp1802"]
local pageram=vis.spaces["pageram"]; local io_sp=cpu.spaces["io"]
local reg={bkg=0,cfc=0,col=0,freshorz=0,line9=0,line16=0,dblpage=0,fresvert=0,cmem=0,dispoff=0,hma=0}
local rd={}; for k,v in pairs(reg) do rd[k]=v end
local snapped=false
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
local coin,start1
for pn,port in pairs(m.ioport.ports) do for fn,fld in pairs(port.fields) do
  if fn=="Coin 1" then coin=fld end; if fn=="1 Player Start" then start1=fld end end end
TAPS={}
TAPS[1]=io_sp:install_write_tap(0x03,0x07,"o",function(o,d,mk)
  if o==3 then local x=d&0xff; reg.bkg=x&7; reg.cfc=(x>>3)&1; reg.dispoff=(x>>4)&1; reg.col=(x>>5)&3; reg.freshorz=(x>>7)&1
  elseif o==5 then local a=rx(); reg.cmem=a&1; reg.line9=(a>>3)&1; reg.line16=(a>>5)&1; reg.dblpage=(a>>6)&1; reg.fresvert=(a>>7)&1
  elseif o==7 then reg.hma=rx()&0x7fc end end)
TAPS[2]=pageram:install_read_tap(0x000,0x7ff,"pr",function(o,d,mk)
  if not snapped then for k,v in pairs(reg) do rd[k]=v end; snapped=true end end)
local f=0; local seen={}
emu.register_frame_done(function()
  f=f+1
  if coin then coin:set_value((f>=150 and f<=180) and 1 or 0) end
  if start1 then start1:set_value((f>=240 and f<=280) and 1 or 0) end
  local k=string.format("col=%d cfc=%d bkg=%d dbl=%d l16=%d fhz=%d fvt=%d l9=%d dispoff=%d hma=0x%x",rd.col,rd.cfc,rd.bkg,rd.dblpage,rd.line16,rd.freshorz,rd.fresvert,rd.line9,rd.dispoff,rd.hma)
  if not seen[k] then seen[k]=f; print(string.format("  f%4d: %s",f,k)) end
  snapped=false
  if f>=2600 then m:exit() end
end)
