-- Sondeo: guarda snapshots a varios tiempos + reporta si page RAM tiene contenido.
local m = manager.machine
local scr = m.screens[":screen"]
local vis = m.devices[":cdp1869"]
local f = 0
local shots = { [300]=true, [600]=true, [1000]=true, [1500]=true, [2000]=true }
emu.register_frame_done(function()
    f = f + 1
    if shots[f] then
        local ps = vis.spaces["pageram"]
        local nonzero = 0
        for i=0,0x3ff do if ps:read_u8(i) ~= 0 then nonzero = nonzero + 1 end end
        print(string.format("frame %d: pageram nonzero=%d", f, nonzero))
        scr:snapshot(string.format("C:/_PROYECTOS/Cidelsa/debug/destryer/raw/mame_snaps/probe_%04d.png", f))
    end
    if f >= 2000 then m:exit() end
end)
