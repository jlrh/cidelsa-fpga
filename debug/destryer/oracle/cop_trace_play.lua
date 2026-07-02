-- oráculo COP402 DURANTE gameplay (inyecta moneda+start). Loga tras frame START_CAP
-- para capturar el COP402 generando sonido (snd varía).
local N=tonumber(os.getenv("COP_N")) or 2000
local START_CAP=tonumber(os.getenv("START_CAP")) or 450
local OUT="C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/cop_trace_mame.txt"
local m=manager.machine; local cop=m.devices[":cop402n"]; local cpu=m.devices[":cdp1802"]
local copprog=cop.spaces["program"]; local io1802=cpu.spaces["io"]
local fh=assert(io.open(OUT,"w")); local cnt=0; local sndcmd=0; local f=0; local cap=false
local coin,start1
for pn,port in pairs(m.ioport.ports) do for fn,fld in pairs(port.fields) do
  if fn=="Coin 1" then coin=fld end; if fn=="1 Player Start" then start1=fld end end end
local function st(n) return cop.state[n].value end
TAPS={}
TAPS[#TAPS+1]=io1802:install_write_tap(0x01,0x01,"snd",function(o,d,mk) sndcmd=(d>>5)&7 end)
TAPS[#TAPS+1]=copprog:install_read_tap(0x000,0x3ff,"cop",function(o,d,mk)
  if not cap or cnt>=N then return end
  if o ~= (st("CURPC")&0x3ff) then return end
  cnt=cnt+1
  fh:write(string.format("%d pc=%03x A=%x B=%02x G=%x Q=%02x EN=%x snd=%d\n",
    cnt,(st("CURPC"))&0x3ff, st("A")&0xf, st("B")&0xff, st("G")&0xf, st("Q")&0xff, st("EN")&0xf, sndcmd))
  if cnt>=N then fh:close(); print(">>> cop_trace_mame.txt: "..cnt.." (gameplay)"); m:exit() end
end)
emu.register_frame_done(function()
  f=f+1
  if coin then coin:set_value((f>=150 and f<=180) and 1 or 0) end
  if start1 then start1:set_value((f>=240 and f<=280) and 1 or 0) end
  if f>=START_CAP then cap=true end
  if f>=1500 then m:exit() end
end)
