local m=manager.machine; local cpu=m.devices[":cdp1802"]; local io_sp=cpu.spaces["io"]; local scr=m.screens[":screen"]
-- listar campos de los ports de entrada
local function list_fields()
  for pn,port in pairs(m.ioport.ports) do
    for fn,fld in pairs(port.fields) do
      print(string.format("  port=%s field='%s' mask=0x%x", pn, fn, fld.mask))
    end
  end
end
print(">>> PORTS/FIELDS:"); list_fields()

-- config de display capturada a mitad de pantalla
local reg={dblpage=0,line9=0,line16=0,freshorz=0,fresvert=0,col=0,cfc=0}
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
TAPS={}
TAPS[1]=io_sp:install_write_tap(0x03,0x07,"cfg",function(o,d,mk)
  if o==3 then reg.cfc=(d>>3)&1; reg.col=(d>>5)&3; reg.freshorz=(d>>7)&1
  elseif o==5 then local a=rx(); reg.line9=(a>>3)&1; reg.line16=(a>>5)&1; reg.dblpage=(a>>6)&1; reg.fresvert=(a>>7)&1 end
end)
local capt={}
local function snap_field()
  if scr:vpos()>=140 and scr:vpos()<=160 then capt={dblpage=reg.dblpage,line9=reg.line9,line16=reg.line16,freshorz=reg.freshorz,fresvert=reg.fresvert,col=reg.col,cfc=reg.cfc} end
end

-- intentar forzar coin1 (EF) y start1 (IN0) por nombre/mask
local coin, start
for pn,port in pairs(m.ioport.ports) do
  for fn,fld in pairs(port.fields) do
    if fn:find("Coin") and not coin then coin=fld end
    if fn:find("Start") and not start then start=fld end
  end
end
print(string.format(">>> coin=%s start=%s", tostring(coin~=nil), tostring(start~=nil)))

local f=0
emu.register_frame_done(function()
  f=f+1
  snap_field()
  if f>=200 and f<=230 and coin then coin:set_value(1) elseif coin then coin:set_value(0) end
  if f>=260 and f<=290 and start then start:set_value(1) elseif start then start:set_value(0) end
  if f==600 then print(string.format(">>> @600 DISPLAY: dbl=%d l9=%d l16=%d fhz=%d fvt=%d col=%d cfc=%d",
     capt.dblpage or -1,capt.line9 or -1,capt.line16 or -1,capt.freshorz or -1,capt.fresvert or -1,capt.col or -1,capt.cfc or -1)); m:exit() end
end)
