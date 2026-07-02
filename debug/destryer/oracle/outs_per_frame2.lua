local m=manager.machine; local cpu=m.devices[":cdp1802"]; local io_sp=cpu.spaces["io"]
local f=0; local cnt=0
TAPS={}
TAPS[1]=io_sp:install_write_tap(0x01,0x07,"opf",function(o,d,mk) cnt=cnt+1 end)
emu.register_frame_done(function()
  f=f+1
  if f>=200 and f<=240 then print(string.format("frame %d: %d OUTs", f, cnt)) end
  cnt=0
  if f>=240 then m:exit() end
end)
