
## A noninteractive demo and in-progress kb/tty drivers so
## far. Hopes: a fast, fun NES Forth akin to durexForth.
#:
## You'll need this software:
CA65 ?= ca65 ## 6502 assembler, in the cc65 suite.
LD65 ?= ld65 ## and its linker.
MESEN ?= Mesen ## NES emulator with debugging features.
#:

# Cartridge configuration:

# I'm not very interested in making a real cart but I'd like
# it to be possible. Need to study the constraints more.
# Sketch: one scratch PRG-RAM bank mostly reserved to compile
# user code. NES powerdown risks PRG-RAM corruption via random
# instructions. Fine for scratch.
#
# In lieu of studying the tape recorder I'd wish for extra
# PRG-RAM banks for long-term user BLOCK storage. Risk of
# rogue bank-switch then corruption is probably astronomical.
# Would be curious.

# https://www.nesdev.org/wiki/Mapper
MAPPER = 0# $smmm: w/ sub. 0 nrom, 1 mmc1, 218 nesmon's
MIRROR = 0# 0/1: horiz/vert, opposite scroll dir
PROM   = 2# $nnn: 16k banks at cpu $8000-bfff, $c000-ffff
CROM   = 1# $nnn: 8k banks on ppu bus
PWRAM  = 7# \ 1=128b ... 6=4k 7=8k 8=16k 9=32k ... 14=1024k
PSRAM  = 0# | save-ram: battery-backed.
CWRAM  = 0# | work-ram: volatile.
CSRAM  = 0# / prg on cpu, chr on ppu bus
PERIPH = 0x23# $0-4f: 0 none, 1 joypad, $23 basic keyboard
# These embed into the INES segment in main.s. Then nes.ld
# arranges bytes in the .nes file and resolves pointers.

CART = -D MAPPER=$(MAPPER) -D MIRROR=$(MIRROR) \
-D PROM=$(PROM) -D PWRAM=$(PWRAM) -D PSRAM=$(PSRAM) \
-D CROM=$(CROM) -D CWRAM=$(CWRAM) -D CSRAM=$(CSRAM) \
-D PERIPH=$(PERIPH)

CAOPT ?= -g -l $@.lst
LDOPT ?= --dbgfile $@.dbg -Ln $@.lbl -m $@.map
LDIN ?= nes.ld o/main.o o/font.o

## Build targets:

o/ff.nes: $(LDIN) | o ## (default)
	$(LD65) -o $@ -C $^  $(LDOPT)

o/%.o: %.s | o        # code and data.
	$(CA65) -o $@ $<  $(CAOPT) $(CART)

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
