# Family Forth

```
$ make help
## Just a noninteractive scrolling demo right now, plus
## *lots* of untested code that is proving fun to write.
## Hoping to be: a fast, fun NES Forth akin to durexForth.

## Makefile variables, you'll need this software:
CA65 ?= ca65 # featureful 6502 assembler, in the cc65 suite
LD65 ?= ld65 # and its linker
MESEN ?= Mesen # NES emulator with debugging features
(...)

$ nix-shell # Get cc65 and Mesen if you have Nix.
$ make run # Look at my silly font scroll, whee!
```

- https://cc65.github.io/
- https://www.mesen.ca/
- https://github.com/jkotlinski/durexforth <- for C64. fun!

License not yet decided.
