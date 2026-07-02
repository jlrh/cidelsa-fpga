local F1=tonumber(os.getenv("F1")) or 40
local m=manager.machine; local cpu=m.devices[":cdp1802"]
local prog=cpu.spaces["program"]; local io_sp=cpu.spaces["io"]
local f=0; local cmem=0
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
local out=io.open("C:/_PROYECTOS/Cidelsa/debug/destryer/play/mame_w.txt","w")
TAPS={}
TAPS[#TAPS+1]=io_sp:install_write_tap(0x05,0x05,"r",function(off,data,mask) cmem=rx()&1 end)
TAPS[#TAPS+1]=prog:install_write_tap(0x2000,0xFFFF,"w",function(off,data,mask)
  if f>F1 then return end
  local t; if off<=0x20ff then t="NVRAM" elseif off>=0xF400 and off<=0xF7FF then t="CHAR" elseif off>=0xF800 then t="PAGE" else t="OTHER" end
  out:write(string.format("%04x %02x %d %s\n", off, data&0xff, cmem, t))
end)
emu.register_frame_done(function() f=f+1; if f>F1 then out:close(); m:exit() end end)
