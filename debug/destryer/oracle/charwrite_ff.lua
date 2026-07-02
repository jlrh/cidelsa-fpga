-- charwrite_ff.lua — replica char_ram_w del CDP1869 (cidelsa) y loguea las escrituras
-- que caen en los glifos 0xbe (0x5f0..0x5f7) y 0xff (0x7f8..0x7ff), con contexto.
-- Para comparar el direccionamiento de escritura de char sim vs MAME en el attract dblpage.
local F1 = tonumber(os.getenv("F1")) or 150
local m   = manager.machine
local cpu = m.devices[":cdp1802"]
local prog = cpu.spaces["program"]
local io_sp = cpu.spaces["io"]
local pageram = m.devices[":cdp1869"].spaces["pageram"]
local f = 0
local cmem, dblpage, pma_reg = 0,0,0
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
local function qval() return cpu.state["Q"].value & 1 end
TAPS={}
-- track cmem/dblpage/pma via OUT5/OUT6
TAPS[#TAPS+1]=io_sp:install_write_tap(0x05,0x06,"r",function(off,data,mask)
  local a=rx()
  if off==5 then cmem=a&1; dblpage=(a>>6)&1; pma_reg = (cmem==1) and (a&0x7ff) or 0
  elseif off==6 then pma_reg=a&0x7ff end
end)
-- char write tap
TAPS[#TAPS+1]=prog:install_write_tap(0xF400,0xF7FF,"cw",function(off,data,mask)
  if f>F1 then return end
  local offset = off - 0xF400          -- 0..0x3ff
  local cma = offset & 0x0f
  local pma
  if cmem==1 then pma = (dblpage==1) and pma_reg or (pma_reg & 0x3ff)
  else pma = offset end
  if dblpage==1 then cma = cma & 0x07 end
  local pmd = pageram:read_u8(pma & 0x7ff)
  local column = ((pma & 0x400) ~= 0) and 0xff or pmd
  local addr = ((column << 3) | (cma & 7)) & 0x7ff
  if (addr>=0x5f0 and addr<=0x5f7) or (addr>=0x7f8 and addr<=0x7ff) then
    print(string.format("f=%d CW addr=%04x cmem=%d dbl=%d pma=%03x pma10=%d pmd=%02x col=%02x cma=%d idx=%03x data=%02x q=%d",
      f, off, cmem, dblpage, pma, (pma>>10)&1, pmd, column, cma, addr, data&0xff, qval()))
  end
end)
emu.register_frame_done(function() f=f+1; if f>F1+1 then m:exit() end end)
