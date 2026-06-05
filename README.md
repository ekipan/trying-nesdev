# Family Forth

```
$ make help
## Aspiring to be: a fast, fun STC Forth for the NES, aping
##   much of durexForth's design.
## Currently: a noninteractive scrolling toy, plus *lots*
##   of untested code that is proving fun to write.

## Makefile variables, you'll need this software:
CA65 ?= ca65 # featureful 6502 assembler, in the cc65 suite
LD65 ?= ld65 # and its linker
MESEN ?= Mesen # NES emulator with debugging features

## Build targets:
o/ff.nes: map.cfg o/main.o o/fat.o | o
run: o/ff.nes # via Mesen.
(...)

$ nix-shell # Get cc65 and Mesen if you have Nix.
$ make run # Look at my silly font scroll, whee!
```

- https://cc65.github.io/
- https://www.mesen.ca/
- https://github.com/jkotlinski/durexforth <- for C64. fun!

License not yet decided.
