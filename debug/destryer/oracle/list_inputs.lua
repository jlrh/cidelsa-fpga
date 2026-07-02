local m=manager.machine
for pn,port in pairs(m.ioport.ports) do for fn,fld in pairs(port.fields) do print(string.format("%s : '%s' 0x%x",pn,fn,fld.mask)) end end
m:exit()
