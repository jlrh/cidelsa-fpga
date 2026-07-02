-- mide ciclos de CPU por frame en MAME (para comparar con ce_cpu/frame del RTL)
local m=manager.machine; local cpu=m.devices[":cdp1802"]
local f=0; local prev=cpu:total_cycles()
emu.register_frame_done(function()
  f=f+1
  local now=cpu:total_cycles(); local d=now-prev; prev=now
  if f>=5 and f<=15 then print(string.format("frame %d: %d cpu-cycles", f, d)) end
  if f>=15 then print(string.format(">>> clock(cpu)=%d Hz", cpu.clock)); m:exit() end
end)
