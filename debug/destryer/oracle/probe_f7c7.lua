-- traza TODA escritura a un set de direcciones char, con frame y pmd en el instante
local TARGET = tonumber(os.getenv("CIDELSA_FRAME")) or 1000
local OUT = "C:/_PROYECTOS/Cidelsa/debug/destryer/dumps/probe_f7c7_mame.txt"
local m=manager.machine; local cpu=m.devices[":cdp1802"]; local vis=m.devices[":cdp1869"]
local pageram=vis.spaces["pageram"]; local prog=cpu.spaces["program"]; local io_sp=cpu.spaces["io"]
local reg={cmem=0,dblpage=0,pma=0}; local f=0
local fh=assert(io.open(OUT,"w"))
local function rx() local x=cpu.state["X"].value&0xf; return cpu.state["R"..x].value&0xffff end
local function qv() return cpu.state["Q"].value&1 end
TAPS={}
TAPS[#TAPS+1]=io_sp:install_write_tap(0x03,0x07,"p_out",function(o,d,mk)
  if o==5 then local a=rx(); reg.cmem=a&1; reg.dblpage=(a>>6)&1; reg.pma=(reg.cmem==1) and (a&0x7ff) or 0
  elseif o==6 then reg.pma=rx()&0x7ff end end)
local WATCH={[0xf7c7]=1,[0xf71f]=1,[0xf677]=1,[0xf5cf]=1,[0xf7d0]=1,[0xf488]=1}
TAPS[#TAPS+1]=prog:install_write_tap(0xF400,0xF7FF,"p_char",function(off,d,mk)
  if WATCH[off] then
    local o=off-0xF400; local cma=o&0xf; local pma
    if reg.cmem==1 then pma=(reg.dblpage==1) and reg.pma or (reg.pma&0x3ff) else pma=o end
    if reg.dblpage==1 then cma=cma&7 end
    local pmd=pageram:read_u8(pma&0x7ff)
    local column=((pma&0x400)~=0) and 0xff or pmd
    local addr=((column<<3)|(cma&7))&0x7ff
    fh:write(string.format("f=%d addr=%04x cmem=%d pma=%03x pmd=%02x col=%02x idx=%03x data=%02x q=%d\n",
      f,off,reg.cmem,pma&0x7ff,pmd,column,addr,d&0xff,qv()))
  end end)
emu.register_frame_done(function() f=f+1; if f>=TARGET then fh:close(); print(">>> probe_f7c7 done f="..f); m:exit() end end)
