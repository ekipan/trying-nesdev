
# Forever TODO: sync this and README with the actual status.

## Just a noninteractive scrolling demo right now, plus
## *lots* of untested code that is proving fun to write.
## Hoping to be: a fast, fun NES Forth akin to durexForth.
#:
## Makefile variables, you'll need this software:

CA65 ?= ca65 # featureful 6502 assembler, in the cc65 suite.
LD65 ?= ld65 # and its linker.
MESEN ?= Mesen # NES emulator with debugging features.

#:
## Build targets:

DEPS ?= link.cfg o/main.o o/fat.o | o

o/ff.nes: $(DEPS) | o # (default)
	$(LD65) --dbgfile $@.dbg -m $@.m -o $@ -C $^

o/%.o: %.s | o
	$(CA65) -g -l $@.l -o $@ $<

o:                  # outputs directory.
	# Try "make help" next for some info.
	mkdir -p $@

# Phonies:

clean:              # remove o.
	$(RM) -r o

run: o/ff.nes       # via Mesen.
	$(MESEN) $< &

all: o/ff.nes

#:
## Info phonies. Not much here yet.

help: # this list.
	@awk '/^##|^[a-z]|\?=/ && !/\^/; /^#:/ {print""}' Makefile ||:

.PHONY: all clean help run
