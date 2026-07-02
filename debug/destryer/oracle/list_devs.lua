local m=manager.machine
print(">>> DEVICES:")
for tag,dev in pairs(m.devices) do print("  "..tag) end
m:exit()
