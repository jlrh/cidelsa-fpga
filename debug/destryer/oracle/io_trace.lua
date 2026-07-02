-- Oráculo de traza de E/S: primeras N operaciones OUT del 1802 (puerto, dato, R[X], PC).
-- Valida que el RTL ejecuta el boot y produce las MISMAS escrituras al 1869.
local N = tonumber(os.getenv("IOTRACE_N")) or 60
local m = manager.machine
local cpu = m.devices[":cdp1802"]
local io_sp = cpu.spaces["io"]
local fh = assert(io.open("C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/io_trace_mame.txt","w"))
local cnt = 0
local function rx()
    local x = cpu.state["X"].value & 0xf
    return cpu.state["R"..x].value & 0xffff
end
TAPS = {}
TAPS[1] = io_sp:install_write_tap(0x01, 0x07, "iotrace", function(offset, data, mask)
    if cnt >= N then return end
    cnt = cnt + 1
    local pc = cpu.state["CURPC"].value & 0xffff
    fh:write(string.format("%d port=%d data=0x%02x rx=0x%04x pc=0x%04x\n",
        cnt, offset, data & 0xff, rx(), pc))
    fh:flush()
    if cnt <= 5 then print(string.format("  OUT#%d port=%d data=0x%02x rx=0x%04x", cnt, offset, data&0xff, rx())) end
end)
emu.register_frame_done(function()
    if cnt >= N then fh:close(); print(">>> io_trace_mame.txt: "..cnt.." OUTs"); m:exit() end
end)
