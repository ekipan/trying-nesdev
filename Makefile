
## Aspiring to be: a fast, fun STC Forth for the NES, aping
##   much of durexForth's design.
## Currently: a noninteractive scrolling toy, plus *lots*
##   of untested code that is proving fun to write.
#:
## Makefile variables, you'll need this software:

CA65 ?= ca65 # featureful 6502 assembler, in the cc65 suite
LD65 ?= ld65 # and its linker
MESEN ?= Mesen # NES emulator with debugging features

#:
## Build targets:

o/ff.nes: link.cfg o/main.o o/fat.o | o
	$(LD65) --dbgfile $@.dbg -m $@.m -o $@ -C $^

o/%.o: %.s | o
	$(CA65) -g -l $@.l -o $@ $<

o:
	# Try "make help" next for some info.
	mkdir -p $@

# Phonies:

clean: # remove o directory.
	$(RM) -r o

all: o/ff.nes

run: o/ff.nes # via Mesen.
	$(MESEN) $< &

#:
## Info phonies. Not much here yet.

help: # this list.
	@awk '/^##|^[a-z]|\?=/ && !/\^/; /^#:/ {print""}' Makefile ||:

.PHONY: all clean help run
