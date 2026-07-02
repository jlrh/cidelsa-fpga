-- Traza de OUTs + R0/R1 (R1 = PC del ISR de interrupción) para localizar la
-- desincronización de interrupción vs mi sim. Loga también un contador de interrupciones.
local N = tonumber(os.getenv("IOTRACE_N")) or 2700
local m = manager.machine
local cpu = m.devices[":cdp1802"]
local io_sp = cpu.spaces["io"]
local fh = assert(io.open("C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/io_trace_r1_mame.txt","w"))
local cnt = 0
local irqs = 0
local prevP = 0
-- contar interrupciones: cada frame, el 1802 entra en interrupción (P pasa a 1 desde !=1
--   con X=2). Muestreamos P por instrucción vía un tap de fetch (lectura de programa en R0/R1).
-- Más simple: registrar en cada OUT el estado actual.
TAPS = {}
TAPS[1] = io_sp:install_write_tap(0x01, 0x07, "iotrace", function(offset, data, mask)
    if cnt >= N then return end
    cnt = cnt + 1
    local pc = cpu.state["CURPC"].value & 0xffff
    local r0 = cpu.state["R0"].value & 0xffff
    local r1 = cpu.state["R1"].value & 0xffff
    local P  = cpu.state["P"].value & 0xf
    local X  = cpu.state["X"].value & 0xf
    fh:write(string.format("%d port=%d data=0x%02x pc=0x%04x R0=0x%04x R1=0x%04x P=%d X=%d\n",
        cnt, offset, data & 0xff, pc, r0, r1, P, X))
end)
emu.register_frame_done(function()
    if cnt >= N then fh:close(); print(">>> io_trace_r1_mame.txt: "..cnt.." OUTs"); m:exit() end
end)
