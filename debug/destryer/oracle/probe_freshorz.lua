-- probe_freshorz.lua — mantiene la config via tap de OUT y la imprime en cada frame_done.
-- Objetivo: ver si freshorz togglea por frame o es constante durante el attract.
local F0 = tonumber(os.getenv("F0")) or 100
local F1 = tonumber(os.getenv("F1")) or 200
local m   = manager.machine
local cpu = m.devices[":cdp1802"]
local io_sp = cpu.spaces["io"]
local f = 0
local freshorz, fresvert, dblpage, line9, bkg, dispoff, col, cfc = 0,0,0,0,0,0,0,0
local nout3, nout5 = 0,0
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
TAPS={}
TAPS[#TAPS+1]=io_sp:install_write_tap(0x03,0x07,"p",function(off,data,mask)
  if off==3 then freshorz=(data>>7)&1; bkg=data&7; dispoff=(data>>4)&1; col=(data>>5)&3; cfc=(data>>3)&1; nout3=nout3+1
  elseif off==5 then local a=rx(); fresvert=(a>>7)&1; dblpage=(a>>6)&1; line9=(a>>3)&1; nout5=nout5+1 end
end)
emu.register_frame_done(function()
  f=f+1
  if f>=F0 and f<=F1 then
    print(string.format("f=%3d freshorz=%d fresvert=%d dblpage=%d line9=%d bkg=%d col=%d cfc=%d dispoff=%d  (nout3=%d nout5=%d)",
      f,freshorz,fresvert,dblpage,line9,bkg,col,cfc,dispoff,nout3,nout5))
  end
  if f>F1 then m:exit() end
end)
