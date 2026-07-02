local m=manager.machine; local cpu=m.devices[":cdp1802"]; local io1802=cpu.spaces["io"]
local f=0; local seen={}
local coin,start1,fire
for pn,port in pairs(m.ioport.ports) do for fn,fld in pairs(port.fields) do
  if fn=="Coin 1" then coin=fld end; if fn=="1 Player Start" then start1=fld end
  if fn:find("Button 1") then fire=fld end end end
TAPS={}
TAPS[1]=io1802:install_write_tap(0x01,0x01,"snd",function(o,d,mk)
  local s=(d>>5)&7
  if s~=0 and not seen[s] then seen[s]=f; print(string.format("  snd=%d @frame %d (data=0x%02x)",s,f,d&0xff)) end
end)
emu.register_frame_done(function()
  f=f+1
  if coin then coin:set_value((f>=150 and f<=180) and 1 or 0) end
  if start1 then start1:set_value((f>=240 and f<=280) and 1 or 0) end
  if fire and f>=350 and (f%20<8) then fire:set_value(1) elseif fire then fire:set_value(0) end  -- disparar
  if f>=2000 then print(">>> fin, frames="..f); m:exit() end
end)
