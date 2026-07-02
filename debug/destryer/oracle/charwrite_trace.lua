-- ============================================================================
--  charwrite_trace.lua — traza TODAS las escrituras CHAR que caen en los glifos
--  redefinibles char 0xbe (idx 0x5f0..0x5f7) y char 0xff (idx 0x7f8..0x7ff),
--  con el MISMO contexto del direccionamiento 1869 que el RTL (cmem, dblpage,
--  pma, pmd, column, cma, addr, data, q). Hasta el frame objetivo.
--  Sirve para comparar write-by-write contra el CHARTRACE del RTL vivo.
--  Frame objetivo por env CIDELSA_FRAME (def 1000).
-- ============================================================================
local TARGET = tonumber(os.getenv("CIDELSA_FRAME")) or 1000
local OUT    = "C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/charwrite_mame.txt"

local m   = manager.machine
local cpu = m.devices[":cdp1802"]
local vis = m.devices[":cdp1869"]
local pageram = vis.spaces["pageram"]
local prog    = cpu.spaces["program"]
local io_sp   = cpu.spaces["io"]

local reg = { cmem=0, dblpage=0, pma=0 }
local f = 0
local fh = assert(io.open(OUT, "w"))

local function rx()
    local x = cpu.state["X"].value & 0xf
    return cpu.state["R"..x].value & 0xffff
end
local function qval() return cpu.state["Q"].value & 1 end

TAPS = {}

-- OUT 3..7: sólo necesitamos cmem/dblpage/pma (out5, out6)
TAPS[#TAPS+1] = io_sp:install_write_tap(0x03, 0x07, "vt_out", function(offset, data, mask)
    local n = offset
    if n == 5 then
        local a = rx()
        reg.cmem=a&1; reg.dblpage=(a>>6)&1
        reg.pma = (reg.cmem==1) and (a & 0x7ff) or 0
    elseif n == 6 then
        reg.pma = rx() & 0x7ff
    end
end)

TAPS[#TAPS+1] = prog:install_write_tap(0xF400, 0xF7FF, "vt_char", function(offset, data, mask)
    local o   = offset - 0xF400
    local cma = o & 0xf
    local pma
    if reg.cmem == 1 then
        pma = (reg.dblpage == 1) and reg.pma or (reg.pma & 0x3ff)
    else
        pma = o
    end
    if reg.dblpage == 1 then cma = cma & 7 end
    local pmd = pageram:read_u8(pma & 0x7ff)
    local column = ((pma & 0x400) ~= 0) and 0xff or pmd
    local addr = ((column << 3) | (cma & 7)) & 0x7ff
    if (addr >= 0x5f0 and addr <= 0x5f7) or (addr >= 0x7f8 and addr <= 0x7ff) then
        fh:write(string.format("CW addr=%04x cmem=%d dbl=%d pma=%03x pma10=%d pmd=%02x col=%02x cma=%d idx=%03x data=%02x q=%d\n",
            offset, reg.cmem, reg.dblpage, pma & 0x7ff, (pma>>10)&1, pmd, column, cma & 7, addr, data & 0xff, qval()))
    end
end)

emu.register_frame_done(function()
    f = f + 1
    if f >= TARGET then
        fh:close()
        print(">>> charwrite_mame.txt escrito hasta frame "..f)
        m:exit()
    end
end)
