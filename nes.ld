MEMORY { # metadata, CPU bus, PPU bus:
    HDR: file = %O, start = 0, size = 16, type = ro, fill = yes;
    C00: file = "", start = $0000, size = $0100, type = rw;
    C01: file = "", start = $0100, size = $0700, type = rw;
    C60: file = "", start = $6000, size = $0100, type = rw;
    C80: file = %O, start = $8000, size = $4000, type = ro, fill = yes;
    CC0: file = %O, start = $C000, size = $4000, type = ro, fill = yes;
    P00: file = %O, start = $0000, size = $2000, type = ro, fill = yes, fillval = $AA;
}
SEGMENTS { # code and data bytes:
    INES:     load = HDR, type = ro; # metadata
    ZEROPAGE: load = C00, type = zp;
    BSS:      load = C01, type = bss;
    DATA:     load = C60, type = bss;
    RODATA:   load = C80, type = ro;
    CODE:     load = CC0, type = ro;
    VECTORS:  load = CC0, type = ro, start = $FFFA;
    FONT:     load = P00, type = ro;
}
