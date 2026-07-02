local m=manager.machine; local cpu=m.devices[":cdp1802"]; local io_sp=cpu.spaces["io"]
local f=0; local cnt=0; local total=0
TAPS={}
TAPS[1]=io_sp:install_write_tap(0x01,0x07,"opf",function(o,d,mk) cnt=cnt+1; total=total+1 end)
emu.register_frame_done(function()
  f=f+1
  if f>=3 and f<=20 then print(string.format("frame %2d: %d OUTs (acum %d)", f, cnt, total)) end
  cnt=0
  if f>=20 then print(">>> fin"); m:exit() end
end)
