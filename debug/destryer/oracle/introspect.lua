-- Introspección v2: superficie de acceso para el volcado de escena.
local done = false
emu.register_frame_done(function()
    if done then return end
    done = true
    local m = manager.machine
    local vis = m.devices[":cdp1869"]
    local cpu = m.devices[":cdp1802"]

    print("=== CDP1869 SPACES ===")
    for nm,sp in pairs(vis.spaces) do print("  vis.space: "..nm) end
    -- intentar leer page RAM
    local ok,err = pcall(function()
        local ps = vis.spaces["pageram"] or vis.spaces["0"] or vis.spaces[0]
        if ps then
            local s=""
            for i=0,15 do s=s..string.format("%02x ", ps:read_u8(i)) end
            print("  pageram[0..15]: "..s)
        else print("  no pageram space by name; keys above") end
    end)
    if not ok then print("  pageram read err: "..tostring(err)) end

    print("=== CDP1802 STATE REGS ===")
    local n=0
    for k,v in pairs(cpu.state) do n=n+1; if n<=60 then print("  state: "..k) end end

    print("=== CPU SPACES ===")
    for nm,sp in pairs(cpu.spaces) do print("  cpu.space: "..nm) end
    -- leer char RAM window por el espacio de programa
    local ok2,err2 = pcall(function()
        local prog = cpu.spaces["program"]
        local s=""
        for i=0,15 do s=s..string.format("%02x ", prog:read_u8(0xF400+i)) end
        print("  prog[0xF400..]: "..s)
        local s2=""
        for i=0,15 do s2=s2..string.format("%02x ", prog:read_u8(0xF800+i)) end
        print("  prog[0xF800..]: "..s2)
    end)
    if not ok2 then print("  prog read err: "..tostring(err2)) end

    print("=== END INTROSPECT ===")
    m:exit()
end)
