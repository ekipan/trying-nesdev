
# Forever TODO: sync this and README with the actual status.

## A noninteractive demo and in-progress kb/tty drivers so
## far. Hopes: a fast, fun NES Forth akin to durexForth.
#:
## You'll need this software:
CA65 ?= ca65 ## 6502 assembler, in the cc65 suite.
LD65 ?= ld65 ## and its linker.
MESEN ?= Mesen ## NES emulator with debugging features.
## also awk and sed for generated source.
#:
## Build targets:

LDIN ?= o/0-link.cfg o/main.o o/fat.o
LDOPT ?= --dbgfile $@.dbg -Ln $@.lbl -m $@.map
CAOPT ?= -g -l $@.lst
CART = -D MAPPER=$(MAPPER) -D MIRROR=$(MIRROR) \
-D PROM=$(PROM) -D PWRAM=$(PWRAM) -D PSRAM=$(PSRAM) \
-D CROM=$(CROM) -D CWRAM=$(CWRAM) -D CSRAM=$(CSRAM) \
-D PERIPH=$(PERIPH) # cartridge configuration (below).

o/ff.nes: $(LDIN) | o ## (default)
	$(LD65) -o $@ -C $^  $(LDOPT)

o/%.o: %.s | o        # code and data.
	$(CA65) -o $@ $<  $(CAOPT) $(CART)

o/0-%: Makefile | o   # embedded in Makefile.
	awk '/^#$(@:o/%=%)/,/^$$/' $< | sed '1d; s/^# //' >$@

all: o/ff.nes

run: o/ff.nes         ## via Mesen.
	$(MESEN) $< &

clean:                ## remove:
	$(RM) -r o

o:                    ## outputs directory.
	# Try "make help" next for some info.
	mkdir -p $@

help:                 # list targets.
	@awk '/^\S/&&/##/; /^#:/{print""}' Makefile ||:

.PHONY: all clean help run

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

# https://www.nesdev.org/wiki/Mapper
MAPPER = 0# $smmm: w/ sub. 0 nrom, 1 mmc1, 218 nesmon's
MIRROR = 0# 0/1: horiz/vert, opposite scroll dir
PROM   = 2# $nnn: 16k banks at cpu $8000-bfff, $c000-ffff
CROM   = 1# $nnn: 8k banks on ppu bus
PWRAM  = 7# \ 0=0 ... 6=4k 7=8k 8=16k 9=32k ... 14=1024k
PSRAM  = 0# | save-ram: battery-backed.
CWRAM  = 0# | work-ram: volatile.
CSRAM  = 0# / prg on cpu, chr on ppu bus
PERIPH = 0x23# $0-4f: 0 none, 1 joypad, $23 basic keyboard

# these are embedded in the INES segment in main.s. then the
# linker script decides where to put the bytes in the binary
# file and resolves pointers between and within segments.
# embedded here so I'm more likely to keep it up to date.
#
# MEMORY: the nes has two address busses: cpu and ppu (video).
# a cart's address-line-to-ram/rom-chip configuration is
# called a mapper. for now, simple 1-to-1 address/rom mapping.
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
#     P2:  file = "", start = $0200, size = $0600, type = rw;
#     P60: file = "", start = $6000, size = $2000, type = rw;
# # cpu rom
#     PG0: file = %O, start = $8000, size = $4000, type = ro, fill = yes;
#     PGK: file = %O, start = $C000, size = $4000, type = ro, fill = yes;
# # ppu
#     CH0: file = %O, start = $0000, size = $2000, type = ro, fill = yes, fillval = $AA;
# }
# SEGMENTS {
#     INES:     type = ro, load = HDR; # metadata
# # cpu ram:
#     ZEROPAGE: type = zp,  load = P0;
#     BSS:      type = bss, load = P2;
#     DATA:     type = bss, load = P60;
# # cpu rom:
#    #DICT:     type = ro, load = PG0, start = $8000;
#     CODE:     type = ro, load = PGK;
#     RODATA:   type = ro, load = PGK, align = $100;
#     VECTORS:  type = ro, load = PGK, start = $FFFA;
# # ppu:
#     FONT:     type = ro, load = CH0;
# }
