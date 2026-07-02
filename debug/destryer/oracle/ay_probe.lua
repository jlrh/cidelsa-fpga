local m=manager.machine
local ay=m.devices[":ay8910"]
print(">>> AY8910 state items:")
local ok=pcall(function() for k,v in pairs(ay.state) do print("  state:",k) end end)
print("  state ok=",ok)
-- intentar leer espacio de I/O del cop402 / registros
local cop=m.devices[":cop402n"]
print(">>> COP402 spaces:"); for k,v in pairs(cop.spaces) do print("  space:",k) end
print(">>> COP402 state (regs):"); pcall(function() for k,v in pairs(cop.state) do io.write(k.." ") end; print() end)
m:exit()
