
# Forever TODO: sync this and README with the actual status.

## Just a noninteractive scrolling demo right now, plus
## *lots* of untested code that is proving fun to write.
## Hoping to be: a fast, fun NES Forth akin to durexForth.
#:
## You'll need this software:
CA65 ?= ca65 # featureful 6502 assembler, in the cc65 suite.
LD65 ?= ld65 # and its linker.
MESEN ?= Mesen # NES emulator with debugging features.
## also awk and sed for generated source.
#:
## Build targets:

COMPILE = $(CA65) -g -l $@.lst -o $@ $<
LDIN = o/0-link.cfg o/1-ines.o o/main.o o/fat.o
LDOPT = --dbgfile $@.dbg -Ln $@.lbl -m $@.map

o/ff.nes: $(LDIN) | o # (default)
	$(LD65) $(LDOPT) -o $@ -C $^
o/%.o: %.s | o       # code and data.
	$(COMPILE)
o/1-%.o: o/0-%.s | o # sources extracted from:
	$(COMPILE)
o/0-%: Makefile | o  # embedded in Makefile.
	awk '/^#$(@:o/%=%)/,/^$$/' $< | sed '1d; s/^# //' >$@
o:                   # outputs directory.
	# Try "make help" next for some info.
	mkdir -p $@

clean:               # remove o.
	$(RM) -r o
run: o/ff.nes        # via Mesen.
	$(MESEN) $< &
all: o/ff.nes # ^

help: # ^
	@awk '/^##|^[a-z]|\?=/ && !/\^/; /^#:/ {print""}' Makefile ||:

.PHONY: all clean help run


# I embed most build boilerplate into Makefile so I'm more
# likely to keep it up to date. probably makes it more
# difficult to configure though.


# nes cartridge configurations vary wildly. emulators support
# a huge range, but I still need to study the constraints of
# a feasibly realizable cart (TODO). I'm not very interested
# in making one but I'd like it to be possible.
#
# one scratch prg-ram bank: oam? drawqueue? blockbuffer?
# the rest to compile user code and dictionary entries into.
# nes powerdown risks prg-ram corruption via random
# instructions. fine for scratch.
#
# in lieu of studying the tape recorder (TODO), I'd wish for
# extra prg-ram banks to store user source code and data
# blocks long term. risk of rogue bank-switch then corruption
# is probably astronomical. would be curious.

#0-ines.s
# Mapper =  1 ; $smmm: w/ sub. 0 nrom, 1 mmc1, 218 nesmon's
# HMirror = 1 ; 0/1: vert/horiz, opposite scroll dir
# PrgRoms = 2 ; $nn:  16k banks at cpu $8000-ffff
# PrgRams = 1 ; $nn:   8k banks at cpu $6000-7fff, w/ battery
# ChrRoms = 1 ; $nn: \ 8k banks on ppu bus
# ChrRams = 0 ; $nn: / usually one or the other
# Periph =  0 ; $0-4f: 0 none, $23 basic keyboard
# .segment "INES" ; binfmt: https://www.nesdev.org/wiki/NES_2.0
#     .byte "NES", $1a, PrgRoms&255, ChrRoms&255 ; 0-5
#     .byte ((Mapper&$f)<<4) | ((PrgRams>0)<<1) | HMirror ; 6
#     .byte ((Mapper>>4)&$f) | 8 ; 7 nes hw, nes format 2.0
#     .byte (Mapper>>8), 0, PrgRams, ChrRams, 0, 0, 0, Periph


# a linker script decides where to put the bytes in the binary
# file and resolves pointers between and within segments.
#
# MEMORY: the nes has two address busses: cpu and ppu (video).
# a cart's address-line-to-ram/rom chip configuration is
# called a mapper:  https://www.nesdev.org/wiki/Mapper
# for now, simple 1-to-1 address-to-rom mapping.
#
# P1: the 6502 cpu owns ram page 1 for the hardware stack.
# I reserve the P1 region from its first half for possible
# reuse by segment variables.
#
# SEGMENTS: data and code bytes, labels, and pointers. a few
# names are special to ca65, eg. pointers into ZEROPAGE
# assemble with 1 opcode byte.
# https://cc65.github.io/doc/ca65.html#.SEGMENT

#0-link.cfg
# MEMORY {
#     HDR: file = %O, start = 0, size = $10, type = ro, fill = yes;
# # cpu ram
#     P0:  file = "", start = $0000, size = $0100, type = rw;
#    #P1:  file = "", start = $0100, size = $0080, type = rw; # note
#     P2:  file = "", start = $0200, size = $0600, type = rw;
#    #WRK: file = "", start = $6000, size = $2000, type = rw;
# # cpu rom
#     PG0: file = %O, start = $8000, size = $4000, type = ro, fill = yes;
#     PGK: file = %O, start = $C000, size = $4000, type = ro, fill = yes;
# # ppu
#     CH0: file = %O, start = $0000, size = $2000, type = ro, fill = yes, fillval = $AA;
# }
# SEGMENTS {
#     INES:     type = ro, load = HDR; # metadata
# # cpu ram:
#     PSTACK:   type = zp, load = P0, start = 0; # for aesthetics
#     ZEROPAGE: type = zp, load = P0;
#    #OUTBUF:   type = bss, load = P1; # 32b
#     QUEUE:    type = bss, load = P2, start = $200;
#     BSS:      type = bss, load = P2;
#     RAMVEC:   type = bss, load = P2, start = $3FB;
#    #BLOCK:    type = bss, load = P2, start = $400; # 1k
#    #OAM:      type = bss, load = WRK; # 256b
# # cpu rom:
#     DICT:     type = ro, load = PG0, start = $8000;
#    #SAMPLES:  type = ro, load = PG0, align = $400;
#     CODE:     type = ro, load = PGK;
#     RODATA:   type = ro, load = PGK, align = $100;
#     ROMVEC:   type = ro, load = PGK, start = $FFFA;
# # ppu:
#     FONT:     type = ro, load = CH0; # ppu
# }
