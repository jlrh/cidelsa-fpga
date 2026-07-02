-- ============================================================================
--  cap_scene_destryer.lua — vuelca una ESCENA de Destroyer para el golden + RTL.
-- ----------------------------------------------------------------------------
--  Reconstruye el estado que screen_update del CDP1869 necesita:
--    - PAGE RAM (1K)  : leída del address-space del device :cdp1869 ("pageram").
--    - CHAR RAM (2K)  : espejada por TAP de escrituras CPU a 0xF400-0xF7FF, con la
--                       MISMA fórmula que cidelsa_charram_w (column<<3 | cma&7).
--    - PCB RAM  (2K)  : idem, valor = Q del 1802 en el instante de la escritura.
--    - Registros out3-7: trackeados por TAP de OUT (ports 3-7 del io space).
--                       OUT3 usa el byte de datos; OUT4-7 usan R[X] (la dirección).
--  Salidas (en debug/destryer/dumps/ + snapshot en raw/mame_snaps/).
--  Frame objetivo por env CIDELSA_FRAME (def 1000); tag por CIDELSA_TAG (def tabla).
-- ============================================================================
local TARGET = tonumber(os.getenv("CIDELSA_FRAME")) or 1000
local TAG    = os.getenv("CIDELSA_TAG") or "tabla"
local DUMPS  = "C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/"
local SNAPS  = "C:/_PROYECTOS/Cidelsa/debug/destryer/raw/mame_snaps/"

local m   = manager.machine
local vis = m.devices[":cdp1869"]
local cpu = m.devices[":cdp1802"]
local scr = m.screens[":screen"]
local pageram = vis.spaces["pageram"]
local prog    = cpu.spaces["program"]
local io_sp   = cpu.spaces["io"]

-- ---- estado de registros (espejo de vis_regs) ----
-- reg     = valor VIVO (lo usa el espejo de CHAR RAM en el instante de escritura).
-- reg_disp = copia tomada DURANTE el display (vpos mid-pantalla) = la config que usa
--            screen_update. Necesario porque el juego cambia regs en vblank (cmem/dblpage
--            para cargar chars, dispoff, etc.) → a fin de frame los valores son transitorios.
local reg = { bkg=0, cfc=0, dispoff=0, col=0, freshorz=0,
              cmem=0, line9=0, line16=0, dblpage=0, fresvert=0,
              pma=0, hma=0,
              toneamp=0, tonefreq=0, toneoff=0, tonediv=0 }
local reg_disp = {}
for k,v in pairs(reg) do reg_disp[k]=v end
local captured_frame = false
local f = 0   -- contador de frames (visible para los taps, para instrumentar)

-- ---- espejos de CHAR/PCB RAM ----
local charram = {}; local pcbram = {}
for i=0,0x7ff do charram[i]=0; pcbram[i]=0 end

local function rx()  -- valor de R[X] (la dirección del bus durante OUT)
    local x = cpu.state["X"].value & 0xf
    return cpu.state["R"..x].value & 0xffff
end
local function qval() return cpu.state["Q"].value & 1 end

-- IMPORTANTE: retener los objetos tap en una tabla global; si se recolectan por GC,
-- MAME los desinstala silenciosamente (causa de char_writes=0 al añadir más taps).
TAPS = {}

-- contadores de diagnóstico por puerto
outcnt = {0,0,0,0,0,0,0,0}
out3_log = 0

-- ---- TAP de OUT (io ports 3..7) ----
TAPS[#TAPS+1] = io_sp:install_write_tap(0x03, 0x07, "vis_out", function(offset, data, mask)
    local n = offset
    outcnt[n+1] = outcnt[n+1] + 1
    if n == 3 and out3_log < 6 then
        out3_log = out3_log + 1
        print(string.format("    [out3 #%d] data=0x%02x  -> freshorz=%d col=%d cfc=%d dispoff=%d bkg=%d  (f=%d vpos=%d)",
            out3_log, data&0xff, (data>>7)&1, (data>>5)&3, (data>>3)&1, (data>>4)&1, data&7, f, scr:vpos()))
    end
    if n == 3 then
        local d = data & 0xff
        reg.bkg=d&7; reg.cfc=(d>>3)&1; reg.dispoff=(d>>4)&1; reg.col=(d>>5)&3; reg.freshorz=(d>>7)&1
    else
        local a = rx()
        if n == 4 then
            reg.toneamp=a&0xf; reg.tonefreq=(a>>4)&7; reg.toneoff=(a>>7)&1; reg.tonediv=(a>>8)&0x7f
        elseif n == 5 then
            reg.cmem=a&1; reg.line9=(a>>3)&1; reg.line16=(a>>5)&1; reg.dblpage=(a>>6)&1; reg.fresvert=(a>>7)&1
            reg.pma = (reg.cmem==1) and (a & 0x7ff) or 0
        elseif n == 6 then
            reg.pma = a & 0x7ff
        elseif n == 7 then
            reg.hma = a & 0x7fc
        end
    end
    -- instrumentación: timeline de OUT3/OUT5 (config de display) vs scanline, frame objetivo
    if f == TARGET-1 and (n==3 or n==5 or n==7) then
        print(string.format("    OUT%d @vpos=%3d  freshorz=%d fresvert=%d line9=%d dblpage=%d dispoff=%d bkg=%d hma=0x%x",
            n, scr:vpos(), reg.freshorz, reg.fresvert, reg.line9, reg.dblpage, reg.dispoff, reg.bkg, reg.hma))
    end
end)

-- ---- captura de la config de DISPLAY: tap de lectura de ROM; cuando vpos está en
--      mitad de pantalla y aún no se ha copiado este frame, snapshot reg -> reg_disp ----
TAPS[#TAPS+1] = prog:install_read_tap(0x0000, 0x1FFF, "vis_dispcfg", function(offset, data, mask)
    if not captured_frame then
        local v = scr:vpos()
        if v >= 80 and v <= 240 then
            for k,val in pairs(reg) do reg_disp[k]=val end
            captured_frame = true
        end
    end
end)

-- ---- TAP de escrituras a CHAR RAM (program 0xF400-0xF7FF) ----
TAPS[#TAPS+1] = prog:install_write_tap(0xF400, 0xF7FF, "vis_char", function(offset, data, mask)
    local o   = offset - 0xF400          -- 0..0x3ff
    local cma = o & 0xf
    local pma
    if reg.cmem == 1 then
        pma = (reg.dblpage == 1) and reg.pma or (reg.pma & 0x3ff)
    else
        pma = o
    end
    local pmd = pageram:read_u8(pma & 0x7ff)
    local column = ((pma & 0x400) ~= 0) and 0xff or pmd
    local addr = ((column << 3) | (cma & 7)) & 0x7ff
    charram[addr] = data & 0xff
    pcbram[addr]  = qval()
    char_writes = char_writes + 1
end)
char_writes = 0

-- ---- volcado al llegar al frame objetivo ----
local function dump_hex(path, tbl, n)
    local fh = assert(io.open(path, "w"))
    for i=0,n-1 do fh:write(string.format("%02x\n", tbl[i] & 0xff)) end
    fh:close()
end

emu.register_frame_done(function()
    f = f + 1
    if f ~= TARGET then
        if f > TARGET then m:exit() end
        captured_frame = false   -- rearmar para el siguiente frame
        return
    end

    -- page RAM (lectura viva)
    local page = {}
    for i=0,0x3ff do page[i] = pageram:read_u8(i) end
    dump_hex(DUMPS.."page_ram.hex", page, 0x400)
    dump_hex(DUMPS.."char_ram.hex", charram, 0x800)
    dump_hex(DUMPS.."pcb_ram.hex",  pcbram,  0x800)

    -- registros: la config de DISPLAY (reg_disp) para los campos que usa screen_update;
    -- cmem/pma/tono no afectan al escaneo de display (se dejan del estado vivo, informativos).
    local fh = assert(io.open(DUMPS.."regs.txt", "w"))
    local disp_fields = {"bkg","cfc","dispoff","col","freshorz","line9","line16","dblpage","fresvert","hma"}
    for _,k in ipairs(disp_fields) do fh:write(string.format("%s=%d\n", k, reg_disp[k])) end
    -- informativos (estado vivo a fin de frame)
    for _,k in ipairs({"cmem","pma","toneamp","tonefreq","toneoff","tonediv"}) do
        fh:write(string.format("%s=%d\n", k, reg[k]))
    end
    fh:close()

    scr:snapshot(SNAPS..TAG..".png")
    -- bitmap CRUDO (sin el escalado de set_default_position) → pixel-exacto para el golden
    local ok_px, pix = pcall(function() return scr:pixels() end)
    if ok_px and pix then
        local pf = assert(io.open(DUMPS.."screen.bin", "wb")); pf:write(pix); pf:close()
        print(string.format("    [pixels] %d bytes  visarea=%dx%d", #pix, scr.width, scr.height))
    else
        print("    [pixels] no disponible: "..tostring(pix))
    end
    print(string.format(">>> escena '%s' frame %d  [DISPLAY] hma=0x%x bkg=%d col=%d cfc=%d freshorz=%d fresvert=%d dblpage=%d line9=%d line16=%d dispoff=%d",
        TAG, f, reg_disp.hma, reg_disp.bkg, reg_disp.col, reg_disp.cfc, reg_disp.freshorz, reg_disp.fresvert, reg_disp.dblpage, reg_disp.line9, reg_disp.line16, reg_disp.dispoff))
    local nz=0; for i=0,0x7ff do if charram[i]~=0 then nz=nz+1 end end
    print(string.format("    [LIVE@end] freshorz=%d fresvert=%d line9=%d dblpage=%d bkg=%d col=%d cfc=%d dispoff=%d cmem=%d  char_nonzero=%d",
        reg.freshorz, reg.fresvert, reg.line9, reg.dblpage, reg.bkg, reg.col, reg.cfc, reg.dispoff, reg.cmem, nz))
    print(string.format("    [OUT counts] o3=%d o4=%d o5=%d o6=%d o7=%d",
        outcnt[4], outcnt[5], outcnt[6], outcnt[7], outcnt[8]))
    m:exit()
end)
