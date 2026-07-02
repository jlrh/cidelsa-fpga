-- oráculo del COP402: traza ejecución (PC,A,B,G,Q,EN) + comando de sonido del 1802.
-- G+Q reconstruyen las escrituras al AY8910 (G=3 latch addr=Q, G=1 write data=Q, G=2 read).
local N=tonumber(os.getenv("COP_N")) or 400
local OUT="C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/cop_trace_mame.txt"
local m=manager.machine; local cop=m.devices[":cop402n"]; local cpu=m.devices[":cdp1802"]
local copprog=cop.spaces["program"]; local io1802=cpu.spaces["io"]
local fh=assert(io.open(OUT,"w")); local cnt=0; local sndcmd=0
local function st(n) return cop.state[n].value end
TAPS={}
-- comando de sonido: 1802 OUT1 → ic32 → m_sound = bits5-7
TAPS[#TAPS+1]=io1802:install_write_tap(0x01,0x01,"snd",function(o,d,mk) sndcmd=(d>>5)&7 end)
-- ejecución COP402: tap de lectura de programa (fetch) → log estado
TAPS[#TAPS+1]=copprog:install_read_tap(0x000,0x3ff,"cop",function(o,d,mk)
  if cnt>=N then return end
  if o ~= (cop.state["CURPC"].value & 0x3ff) then return end   -- solo instrucciones EJECUTADAS
  cnt=cnt+1
  fh:write(string.format("%d pc=%03x A=%x B=%02x G=%x Q=%02x EN=%x snd=%d\n",
    cnt, (cop.state["CURPC"].value)&0x3ff, st("A")&0xf, st("B")&0xff, st("G")&0xf, st("Q")&0xff, st("EN")&0xf, sndcmd))
  if cnt>=N then fh:close(); print(">>> cop_trace_mame.txt: "..cnt.." pasos"); m:exit() end
end)
emu.register_frame_done(function() if cnt>=N then m:exit() end end)
