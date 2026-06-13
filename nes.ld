MEMORY { # metadata, CPU bus, PPU bus:
    HDR: file = %O, start = 0, size = $10, type = ro, fill = yes;
    C00: file = "", start = $0000, size = $0100, type = rw;
    C02: file = "", start = $0200, size = $0600, type = rw;
    C60: file = "", start = $6000, size = $0100, type = rw;
    C80: file = %O, start = $8000, size = $4000, type = ro, fill = yes;
    CC0: file = %O, start = $C000, size = $4000, type = ro, fill = yes;
    P00: file = %O, start = $0000, size = $2000, type = ro, fill = yes, fillval = $AA;
}
SEGMENTS { # code and data bytes:
    INES:     type = ro, load = HDR; # metadata
    ZEROPAGE: type = zp,  load = C00;
    BSS:      type = bss, load = C02, align = $100;
    DATA:     type = bss, load = C60;
    CODE:     type = ro, load = CC0;
    RODATA:   type = ro, load = CC0;
    VECTORS:  type = ro, load = CC0, start = $FFFA;
    FONT:     type = ro, load = P00;
}
