
; experiments and studies towards a family forth.
; just a noninteractive scrolling demo so far (TODO).
; a goal is to port <https://github.com/ekipan/sss> to it.
; lots of TODOs are design tradeoffs I need to consider.
;
; to jump around, grep for:
; /code_label:/ /DataLabel:/ /ConstantLabel =/

; time for a bad first impression! code *should* be dense:
.macro _ I,J,K,L,M,N,O,P ; list of instructions.
    .if .not .blank({I}) ; up to 8:
        I
        _ J,K,L,M,N,O,P
    .endif ; eg: _ pha, txa, pha, tya, pha
.endmacro  ; eg: _ jsr foo, jsr bar, jmp qux
; rule: loads at start, 0/1 branches at end.

; it does break the debugger's source view but I've found
; Mesen's disassembly view to be sufficient for my needs.
; might reconsider if it becomes a problem. dense code ahead.

; more macros planned: dict assembly, more shenanigans.

; MEMORY MAP ------------------------------------------------

.data ; $6000-60ff scratch buffers on cart.

Palette: .res 32 ; to upload to ppu.
KbPrev:  .res 9 ; \ 72 bits array of scanned keystates.
KbHeld:  .res 9 ; / 0 = unheld, 1 = held.
KbDown:  .res 9 ; precomputed down-edges Prev->Held.

; then $6100-7fff reserved for scratch to compile user
; programs into. long term program storage should be in
; source form, via forth's BLOCK mechanism (once implemented),
; recompiled on-the-fly.

.bss ; $200-7ff scratch buffers on mainboard.

Oam:   .res 256  ; sprites data, at $200 conventionally.
VCmds: .res 256  ; encoded drawing commands queue.
       .res 1024 ; (planned location of forth block buffer.)

.zeropage ; $00-ff system state.

; registers:
;   x    param stack depth,
;   y/a  scratch, often: y=[H], a=[L].

; forth variables.
     .res 32
L:   .res 32 ; \ push-down, x-indexed, split parameter stack
H:           ; / to pass data between words. depth 1: x = $ff.
W:   .res 2  ; then six bytes of scratch, including:
Dst: .res 2  ; \ pointers for y-indexed
Src: .res 2  ; / transfer of multiple bytes.
; planned: Base, Here, Latest, Pending, InPtr, InEnd.

; interrupt routine scratch space.
V: .res 3 ; draw.
K: .res 2 ; keyboard scanner.

; global configuration:
Config: .res 1 ; %inxxxxxp  custom irq/nmi, upload palettes.
Nmi:    .res 2 ; \ handler routine pointers. set Config
Irq:    .res 2 ; / to 0 first to update atomically.
; after palette upload, draw resets Config.0.

; video driver:
Mutex:  .res 1 ; nonzero: nmi locked, plus draw tally.
; a degenerate draw queue eventually tallies Mutex to 128+,
; the draw interpreter abandons, nmi recovers. TODO xref
Frames: .res 1 ; counter for synching or delaying.
VCtrl:  .res 1 ; \ shadow registers. sent next draw, except
VMask:  .res 1 ; | VCtrl.7 ignored: nmi is kept enabled.
VSclX:  .res 1 ; | careful of data races. for synchronous
VSclY:  .res 1 ; / drawing: 0->VMask, vsync, inc Mutex.
; $0-ff VCmds queue indices:
VHead:   .res 1 ; 1) main appends commands here.
VCommit: .res 1 ; 2) main moves this fwd to publish to draw.
VTail:   .res 1 ; 3) draw interprets and moves fwd.
; conceptually tail <= commit <= head, though since they
; wrap in memory that'll often not be literally true.

; tty driver:
CsrCol: .res 1 ; 0-31, width of screen.
CsrRow: .res 1 ; 0-253, except seam rows 30,31,62,63 etc
; vaddr calc drops CsrRow.6-7, so effectively 0-29,32-61.
; last two columns are in overscan caution zone.
; https://www.nesdev.org/wiki/Overscan
; TODO reconsider design, might fix CsrRow in 0-59 instead.

; current plans for rom space:
;
; $8000-bfff
;     rom dictionary, then blocks of help text, sample code,
;     etc. ideally extra banks, copied into $400 buffer.
; $c000-ffff
;     nes hardware drivers and forth kernel.

.code ; FORTH -----------------------------------------------

; planned: core.s stack/math/memory, ui.s interpreter/compiler.

push_ya: ; push/put_ya/na/a for assembly literals.
    dex
put_ya:
    sty H,x
    sta L,x
    rts

plus: ; ( n1 n0 -- n1+n0 ) addition.
    clc
    lda L+0,x
    adc L+1,x
    sta L+1,x
    lda H+0,x
    adc H+1,x
    sta H+1,x
    inx
    rts

.code ; KB DRIVER -------------------------------------------

; https://www.nesdev.org/wiki/Family_BASIC_Keyboard#Usage
; https://lira.kraamwinkel.be/articles/nes_keyboard
; not much here yet. experimenting.

;            cycles per line | cumulative
wait_50c: nop          ;  2c |  8c <- 6c jsr wait_50c
          jsr wait_12c ; 12c | 20c
wait_36c: jsr wait_12c ; 12c | 32c 18c <- 6c jsr wait_36c
          jsr wait_12c ; 12c | 44c 30c
wait_12c: rts          ;  6c | 50c 36c 12c <- 6c jsr wait_12c

Joy1 = $4016
Joy2 = $4017

kb_stopscan: ; 98c: flag keys: rshift->bcc, stop->beq.
    _ lda #5, sta Joy1, jsr wait_12c ; reset to row 0.
    _ lda #6, sta Joy1, jsr wait_50c, lda Joy2 ; read col 1.
kb_flags: ; %xxxsxrxx <- stop and rshift keys.
    _ lsr, lsr, lsr, and #2, rts ; nc=rshift, z=stop.

kb_fullscan: ; >1200c: scan the entire keyboard.
    ; 9 rows * 2 cols * 4 bits = 72 keys.
    _ lda #5, sta Joy1 ; reset keyboard to row 0.
    jsr wait_12c
    _ lda #4, sta Joy1 ; strobe column 0. wait 50c:
    ; interleave work while waiting for the matrix to settle:
    ; cycle counts:     line accum
    jsr wait_36c       ; 36c 36c
    _ bit 0, ldy #8    ;  5c 41c  scan 9 rows: 8-0.
:   lda KbHeld,y       ;  4c 45c  \ save previous scan
    sta KbPrev,y       ;  5c 50c  / while we're here.
    _ lda Joy2, sta K  ; read column 0: %...kkkk. 0 = held
    _ lda #6, sta Joy1 ; strobe column 1. wait 50c:
    jsr wait_36c       ; 36c 36c
    _ lda K, asl, asl  ;  7c 43c  %.kkkk.00 <- column 0
    _ asl, and #$f0    ;  4c 47c  %kkkk0000
    sta K              ;  3c 50c
    _ lda Joy2, sta K+1 ; read column 1: %...kkkk. 0 = held
    _ lda #4, sta Joy1 ; strobe next row column 0, wait 50c:
    _ lda K+1, lsr     ;  5c  5c  %0...kkkk <- column 1
    _ and #$0f, ora K  ;  5c 10c  %kkkkkkkk
    eor #$ff           ;  2c 12c  1 = curr held
    sta KbHeld,y       ;  5c 17c
    lda KbPrev,y       ;  4c 21c  1 = prev held
    eor #$ff           ;  2c 23c  1 = prev unheld
    and KbHeld,y       ;  4c 27c  1 = prev unheld & curr held
    sta KbDown,y       ;  5c 32c  i.e. pressed
    _ nop, nop         ;  4c 36c
    _ dey, bpl :-      ;  5c 41c -> : 4c+5c 50c  more rows?
    ; TODO scan the press events and push to a keys buffer.
    _ lda KbHeld+8, asl, eor #$ff ; restore raw row 0 col 1.
    jmp kb_flags ; nc=rshift, z=stop.

.code ; VIDEO DRIVER ----------------------------------------

; https://www.nesdev.org/wiki/PPU
; the picture processing unit rejects i/o while drawing the
; screen, draw commands must be sent during 2270c vblank, so
; I encode them into a ring buffer to send asynchronously.
;
; https://github.com/bbbradsmith/NES-ca65-example
; /blob/1bb961dcdf317f39460c0c28a13f33a82feb29c4/example.s#L200-L232
; design grown out from this, do refer to it!

; https://www.nesdev.org/wiki/PPU_registers
PpuCtrl =   $2000 ; %n.tbsvyx nmi tall bgpat sprpat vert yxtbl
PpuMask =   $2001 ; %rgbsbllg dimrgb spr bg leftcol greysc
PpuStatus = $2002 ; %vzo..... vblank zerohit overflow
OamAddr =   $2003 ; ppu write offset, nonzero corrupts oam!
PpuScroll = $2005 ; send x then y \ touch PpuStatus
PpuAddr =   $2006 ; addrh, addrl  / to reset order latch
PpuData =   $2007 ; increments by 1 or 32 (PpuCtrl vert)
OamDma =    $4014 ; (cpu) page to transfer to ppu

; VCmds encodings:
; $0-3f: set PpuAddr, other opcodes far away so it's less
; likely overflowed addresses will be misinterpreted:
VHoriz = $a0 ; \ reset/set increment mode
VVert =  $a1 ; / bit PpuCtrl.1 (+1/32)
VSend =  $a2 ; args: len val1 val2 val3 ...
VFill =  $a3 ; args: len val
VMove =  $a4 ; args: len addrh addrl
VPace =  $a5 ; stop drawing until next frame

draw: ; ~2240c left after nmi prologue.
    _ lda #1, sta Mutex ; lock nmi for synch'd draw in main.
    bit PpuStatus ; reset PpuAddr/PpuScroll write latch.
    ; load sprites:
    _ lda VMask, sta PpuMask ; bg/sprites on/off
    _ and #$10, beq :+ ; sprites disabled? -> skip dma
    _ lda #$00, sta OamAddr ; \ costs
    _ lda Oam, sta OamDma   ; / 521c
:   ; load palette:
    _ lda #1, and Config, beq :++ ; upload palette?
    _ lda #$3f, ldy #0, sta PpuAddr, sty PpuAddr ; $3f00-3f1f
    _ sty PpuCtrl, dec Config ; horiz mode, clear flag, upload:
:   lda Palette,y ; \ txfer   4c \ 15c * 32 = 480c
    sta PpuData   ; / byte    4c | TODO unroll?
    _ iny, cpy #$20, bne :- ; 7c / +138 bytes -160 cycles
:   ; save pstack, interpret draw commands, advance tail:
    _ txa, pha, ldx VTail, jsr @horiz, stx VTail, pla, tax
    ; vblank is possibly blown. construct queues carefully!
    ; restore main's configured drawing mode, vblank willing:
    _ lda VCtrl, ora #$80, sta PpuCtrl
    ; https://www.nesdev.org/wiki/PPU_scrolling#Frequent_pitfalls
    bit PpuStatus
    _ lda VSclX, sta PpuScroll ; shares PpuAddr register,
    _ lda VSclY, sta PpuScroll ; must set *after* draw.
    ; restore invariant: caller can unlock with dec Mutex.
    _ lda #1, sta Mutex ; remove command tally.
    rts

; interpreter loop inlined into most common command set_addr,
; in the middle for branch range reasons.

@horiz: ; incrmode bit clear (+1), default.
    ; nmi always enabled $80:
    _ lda VCtrl, ora #$80, and #$fb, sta PpuCtrl
    bne @loop
@vert: ; incrmode bit set (+32)
    _ lda VCtrl, ora #$84, sta PpuCtrl
    bne @loop
@send: ; (x)y=len val1 val2 val3 ...
:   inx
    lda VCmds,x     ; val#
    _ sta PpuData, dey, bne :-
    beq @inx_and_loop
@fill: ; (x)y=len val
    inx
    lda VCmds,x     ; val
:   _ sta PpuData, dey, bne :-
    beq @inx_and_loop
@set_addr: ; a=$hh (x)y=$ll
    ; rely on caller to reset latch, save 4c:
    ;bit PpuStatus ; draw bugs? uncomment first (!!)
    _ sta PpuAddr, sty PpuAddr
  @inx_and_loop:
    inx
  @loop:
    inc Mutex       ; reuse nmi lock to tally finished commands
    bmi @abandon    ; >127? probably a runaway queue
  @decode: ; x = cursor into page-aligned ring buffer.
    _ cpx VCommit, beq @rts ; no work left to do?
    ; command bytes:  (x)opcode (arg1 arg2 ...)
    lda VCmds,x     ; (x)a=opcode (arg1 ...)
    inx             ; a=opcode (x)(arg1 ...)
    ldy VCmds,x     ; a=opcode (x)y=(arg1) (...)
    ; in order of likeliness, to squeeze cycles:
    _ cmp #$40, bcc @set_addr ; $0-3f, valid ppu page?
    _ cmp #VSend, beq @send   ; workhorse draw
    _ cmp #VFill, beq @fill   ; clearing/blocking out
    _ cmp #VPace, beq @pace   ; separate batches
    _ cmp #VMove, beq @move   ; usually during setup
    _ cmp #VVert, beq @vert   ; switch to columns
    _ cmp #VHoriz, beq @horiz ; back to default
    ; malformed command.
  @abandon:
    ldx VCommit
  @rts:
    rts
@move: ; (x)y=len $hh $ll
    sty V+2     ; len
    inx
    lda VCmds,x ; $hh
    sta V+1     ; read addr high
    inx
    lda VCmds,x ; $ll
    sta V       ; read addr low
    ldy #0      ; scan fwd from 0 to len:
:   lda (V),y
    _ sta PpuData, iny, cpy V+2, bne :-
    beq @inx_and_loop
@pace: ; end frame and defer to next nmi if we've drawn
    ; Mutex: draw stores 1, @horiz inc's, so 2 = no draws:
    _ lda Mutex, cmp #$02, beq @decode ; no draws yet?
    rts

; sending, synching:

to_v: ; ( addr -- ) append address to queue.
    Lda H,x         ; queue expects big-endian!
    jsr a_to_v
c_to_v: ; ( c -- ) append byte to queue.
    lda L,x
    inx
a_to_v:
    ldy VHead
    sta VCmds,y
    iny             ; full page buffer, expects wraparound.
    sty VHead
    rts

vcommit: ; ( -- ) send queued draw commands.
    _ lda VHead, sta VCommit, rts

vsync: ; ( -- ) wait for next vblank.
    _ lda #0, sta Mutex ; TODO stash and restore?
    lda Frames
:   _ cmp Frames, beq :-
    rts

.rodata ; TTY DRIVER ----------------------------------------

RomPalette:
    .repeat 8
        .byte $0F, $29, $17, $20
    .endrepeat

.code

page: ; ( -- ) init and clear the screen.
    ; called on reset, must enable nmi directly! but *also*
    ; must be callable during normal interpreter use. ~0.6f.
    _ ldy #32, lda #1, sta Mutex, sta Config ; upload palette:
:   lda RomPalette,y ; copy initial palette
    sta Palette,y    ; to ram buffer.
    _ dey, bpl :-
    _ lda #0, sta VMask, sta CsrRow, sta CsrCol, sta VSclY
    _ lda #$f8, sta VSclX ; inside overscan, TODO compute y.
    _ lda VCommit, sta VTail, sta VHead ; delete the queue.
    _ lda #$80, sta VCtrl, sta PpuCtrl ; enable nmi.
    jsr vsync ; also frees the Mutex.
    ; clear nametables 1 and 2, see illustration below:
    _ stx W ; save pstack
    _ ldy #$24, lda #$00, bit PpuStatus, sty PpuAddr, sta PpuAddr
    _ ldy #$08, ldx #$00, ;lda #$00
:   stx PpuData ; TODO test pattern: stx, clear: sta
    _ inx, bne :- ; 256 bytes
    _ dey, bne :- ; 8 pages = ntb1/2
    _ ldx W ; restore pstack
    _ lda #$0a, sta VMask ; bg on, sprites off
    rts

; nw ntb0 -> [ $2000-23ff ][ $2400-27ff ] <- ne ntb1  \ 1k
; sw ntb2 -> [ $2800-2bff ][ $2c00-2fff ] <- se ntb3  / each
;
; most carts map nametables 0-3 to the ppu internal 2k,
; mirroring either horizontally or vertically. ntb1 and 2 are
; contiguous in memory and pair with both configurations.

csr_vaddr: ; put cursor vaddr onto draw queue.
    _ ldy CsrRow, lda CsrCol
ya_vaddr:
    sta W+1 ; compute: $2400 + ((y & 63) << 5 | a)
    _ lda #$00, sta W           ; W %00000000  y %xxrrrrrr
    _ tya, asl, asl, asl, rol W ; W %0000000r  a %rrrrr000
    _ asl, rol W, asl, rol W    ; W %00000rrr  a %rrr00000
    _ ldy W, ora W+1, jsr push_ya ; ( offset )
    _ ldy #$24, lda #$00, jsr push_ya ; ( offset base )
    _ jsr plus, jmp to_v

rawemit: ; ( c -- ) display a character.
    _ jsr csr_vaddr, inc CsrCol
    _ lda CsrCol, cmp #32, bcc :+ ; still on screen?
    jsr cr ; no: go to next line
:   _ lda #VSend, jsr a_to_v, lda #1, jsr a_to_v ; send one
    lda L,x                        ; stack-taken
    _ inx, jsr a_to_v, jmp vcommit ; character

cr: ; ( -- ) move the cursor to the start of next line.
    _ lda #VPace, jsr a_to_v ; 64b is risky, pace before/after.
    _ lda #$00, sta CsrCol   ; col = 0, increment row:
    _ ldy CsrRow, jsr @iny, sty CsrRow, jsr @clear ; and clear.
    _ ldy CsrRow, jsr @iny, jsr @clear ; and below screen.
    ; TODO scroll.
    _ lda #VPace, jsr a_to_v, jmp vcommit
@iny:
    _ iny, tya, and #31, cmp #30, bcc :+ ; still in-screen?
    _ iny, iny ; pass over attrtable seam.
:   rts
@clear:
    _ lda #0, jsr ya_vaddr   ; at row address:
    _ lda #VFill, jsr a_to_v ; fill
    _ lda #32, jsr a_to_v    ; an entire row
    _ lda #' ', jmp a_to_v   ; with spaces

.code ; MAIN ------------------------------------------------

main:
    _ lda #1, jsr add_y, jsr vsync, jmp main

add_y: ; scly += a, [-16..16] for correct seam jump.
    clc
    adc VSclY
    tay
    cmp #$f0
    bcc :+    ; not between screens?
    sbc #$f0  ; a = a-240-(1-c)
    tay
    lda #2
    eor VCtrl ; flip
    sta VCtrl ; ntbl \ data
:   sty VSclY ;      / race 3c
    rts

DmcFreq = $4010

reset: ; just powered on, turn off all the things:
    _ sei, cld ; irq, decimal mode
    _ ldx #$ff, txs ; clear return stack
    _ ldx #$40, stx Joy2 ; sound, and screen:
    _ ldx #$00, stx DmcFreq, stx PpuCtrl, stx PpuMask
    ; TODO init banks?
    ; wait 2 frames for ppu, init ram in the meantime.
    ; banging the PpuStatus vblank bit risks a missed frame.
    ; needed for reset but runtime will track via Frames.
    bit PpuStatus
:   _ bit PpuStatus, bpl :- ; first frame
    lda #0
:   sta $000,x
    sta $100,x
    sta $200,x
    sta $300,x
    sta $400,x
    sta $500,x
    sta $600,x
    sta $700,x
    sta $6000,x
    _ inx, bne :-
:   _ bit PpuStatus, bpl :- ; second frame
    _ jsr page, jmp main ; clear bg, start nmi, start main

nmi: ; 2270c deadline to finish drawing
    _ bit Config, bvc :+ ; default nmi service?
    jmp (Nmi) ; no, custom
:   _ pha, tya, pha ; subroutines responsible for x.
    _ lda Mutex, bne :+ ; re-entered?
    inc Frames ; notify main a vblank happened.
    jsr draw   ; store 1 in Mutex and process queue.
    ; TODO poll Joy1? sound?
    jsr kb_fullscan ; >1200c, 10.6 scanlines
    ; jsr kb_stopscan ; TODO configurable scan type.
    beq reset ; pressed stop? TODO recover instead.
    _ lda #0, sta Mutex ; unlock next frame
:   _ pla, tay, pla, rti

irq:
    _ bit Config, bpl :+
    jmp (Irq)
:   rti

; nes hardware and romfile boilerplate:

.segment "VECTORS"
    .addr nmi   ; at vblank
    .addr reset ; at power on and reset
    .addr irq   ; unused by default

; see Makefile for cart configuration defines.
.segment "INES" ; https://www.nesdev.org/wiki/NES_2.0
    .byte "NES", $1a, PROM&255, CROM&255 ; 0-5
    .byte ((MAPPER&$f)<<4) | ((PSRAM+CSRAM>0)<<1) | MIRROR ; 6
    .byte ((MAPPER>>4)&$f) | 8 ; 7: hw nes, binfmt nes2.0
    .byte (MAPPER>>8), ((PROM>>4)&$f0)|(CROM>>8)&$f ; 8-9
    .byte (PSRAM<<4)|PWRAM, (CSRAM<<4)|CWRAM ; 10-11
    .byte 0, 0, 0, PERIPH ; 12-15
