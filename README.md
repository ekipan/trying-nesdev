# NesDev Experiments

```
$ make help
## A noninteractive demo and in-progress kb/tty drivers so
## far. Hopes: a fast, fun NES Forth akin to durexForth.

## You'll need this software:
CA65 ?= ca65 ## 6502 assembler, in the cc65 suite.
LD65 ?= ld65 ## and its linker.
MESEN ?= Mesen ## NES emulator with debugging features.
(...)

$ nix-shell # Get cc65 and Mesen if you have Nix.
$ # or get them with your favorite package manaager.
$ make run # Look at the text scroll!
```

- https://cc65.github.io/
- https://www.mesen.ca/
- https://github.com/jkotlinski/durexforth <- for C64. fun!

License not yet decided.
