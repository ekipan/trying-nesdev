
; experiments and studies towards a family forth.
; just a noninteractive scrolling demo so far (TODO).
; a goal is to port <https://github.com/ekipan/sss> to it.
;
; to jump around, grep for:
; /code_label:/ /DEF forth_code_label/ /"FORTH-WORD"/
; /DataLabel:/ /ConstantLabel =/ /MACRO /

; MACROS ----------------------------------------------------

; time for a bad first impression! code *should* be dense:
.macro _ I,J,K,L,M,N,O,P ; list of instructions.
    .if .not .blank({I}) ; up to 8:
        I
        _ J,K,L,M,N,O,P
    .endif ; eg: _ pha, txa, pha, tya, pha
.endmacro  ; eg: _ jsr foo, jsr bar, jmp qux
; rule: loads at start, 0/1 branches at end.

; inserted opcodes overlap and skip next instruction:
.define JMP1 .byte $24 ; bit zp  ; 1 operand byte
.define JMP2 .byte $2C ; bit abs ; 2 operand bytes
; to save code versus a jmp over another entrypoint.

; wordlist contiguous through ram/rom boundary at $8000.
; assembles up into rom, runtime prepends down into ram.
; `find` scans fwd until a `0` XT after the last rom word.

.macro DEF XT, NAME, FLAGS ; assemble an entry into DICT rom.
    .pushseg
    .segment "DICT" ; a nametoken (nt) is an entry address:
        .addr XT    ; execution token is a code address
        .byte (FLAGS+0) | .strlen(NAME), NAME ; blank needs +0
    .popseg ; code follows back in original segment:
    XT:
.endmacro ; eg: foo: DEF "FOO" ; ( a -- b ) does foo.
; xt field first makes an nt a direct xt pointer: >XT = @

; TODO write `find` then put these there
; Immediate = $80 ; flag: execute even in compile mode
; NeverTco =  $40 ; flag: never tail-call-optimize into a jmp
; Hidden =    $20 ; flag: skipped by find
; Length =    $1f ; mask: up to 31 character names

.macro CONSTANT LABEL_EQ, VALUE ; push value to pstack.
    _ lda #<VALUE, ldy #>VALUE, jmp push_ya
    LABEL_EQ VALUE
.endmacro ; eg: ; DEF foo, "FOO" ; CONSTANT Foo =, 123
; integrated "=" is weird but greppable. TODO optimize byte?

.macro CVALUE ADDR ; fetch unsigned byte value from ram.
    _ lda abs:ADDR, jmp push_a
.endmacro ; wasted abs byte for runtime to store through.

.macro VALUE ADDR ; fetch cell value from ram.
    _ ldy abs:ADDR+1, lda ADDR, jmp push_ya
.endmacro ; runtime can detect size by first opcode.

; CORE ------------------------------------------------------

.segment "PSTACK": zp ; registers: x param stack depth,
     .res 32          ;  y/a scratch, often: y=[H], a=[L].
L:   .res 32 ; \ push-down, x-indexed, split parameter stack
H:           ; / to pass data between words. depth 1: x = $ff.
W:   .res 2  ; then six bytes of scratch, including:
Dst: .res 2  ; \ load/store pointers for y-indexed
Src: .res 2  ; / transfer of multiple bytes.

.segment "CODE"
DEF store, "!" ; ( n addr -- ) store n at addr.
    lda L,x
    ldy H,x
    inx             ; drop addr
store_ya: ; ( n -- ) store at y:a.
    sta Dst
    sty Dst+1
    ldy #0
    lda L,x
    sta (Dst),y
    iny
    lda H,x
    sta (Dst),y
    inx             ; drop n
    rts

DEF fetch, "@" ; ( addr -- n ) fetch n from addr.
    lda L,x
    ldy H,x
    JMP1
fetch_ya: ; ( -- n ) fetch from y:a.
    dex             ; add empty slot
    sta Src
    sty Src+1
    ldy #0
    lda (Src),y
    sta L,x
    lda (Src+1),y
    sta H,x
    rts

DEF c_store, "C!" ; ( c addr -- ) store c at addr.
    lda L+0,x       ; L: ..[ll]cc   H:  .. hh 00
    sta H-1,x       ;    .. ll cc      [ll]hh 00
    lda L+1,x       ;    .. ll[cc]      ll hh 00
    sta (H-1,x)     ;    .. ll cc      [ll hh]00
    _ inx, inx      ; drop c and addr.
    rts

DEF c_fetch, "C@" ; ( addr -- c ) fetch c from addr.
    lda L+0,x       ; L: ..[ll]   H:  .. hh
    sta H-1,x       ;    .. ll       [ll]hh
    lda (H-1,x)     ;    .. ll       [ll hh]
    jmp put_a

DEF two_minus, "2-" ; ( n -- n-2 ) subtract 2.
    jsr one_minus
DEF one_minus, "1-" ; ( n -- n-1 ) subtract 1.
    dec L,x
    bne :+
    dec H,x
:   rts

DEF two_plus, "2+" ; ( n -- n+2 ) add 2.
    jsr one_plus
DEF one_plus, "1+" ; ( n -- n+1 ) add 1.
    inc L,x
    bne :+
    inc H,x
:   rts

DEF four_div, "4/" ; ( n -- n/4 ) signed right shift.
    jsr two_div
DEF two_div, "2/" ; ( n -- n/2 )
    lda #$80
    cmp H,x         ; carry = H+x.7
    ror H,x
    ror L,x
    rts

DEF four_times, "4*" ; ( n -- n*4 ) left shift.
    jsr two_times
DEF two_times, "2*" ; ( n -- n*2 )
    asl L,x
    rol H,x
    rts

push_ya: ; push/put_ya/na/a for assembly literals.
    dex
put_ya:
    sty H,x
    sta L,x
    rts

; forth flags, to be branched to from testing words:

DEF neg_one, "-1" ; ( -- -1 )
    lda #$ff
push_na:
    dex
put_na:
    ldy #$ff
    sty H,x
    sta L,x
    rts

DEF zero, "0" ; ( -- 0 )
    lda #0
push_a:
    dex
put_a:
    ldy #0
    sty H,x
    sta L,x
    rts

DEF plus, "+" ; ( n1 n0 -- n1+n0 ) addition.
    clc
    lda L+0,x
    adc L+1,x
    sta L+1,x
    lda H+0,x
    adc H+1,x
    sta H+1,x
    inx
    rts

; VIDEO DRIVER ----------------------------------------------

; the picture processing unit rejects i/o while drawing the
; screen, draw commands must be sent during 2270c vblank, so
; I encode them into a ring buffer to send asynchronously.

.segment "QUEUE"
     .align 256 ; page-aligned so indices wrap.
VCmds: .res 256 ; encoded drawing commands queue.

VHoriz = $40 ; \ set PpuCtrl
VVert =  $41 ; / direction bit
VSend =  $42 ; args: len val1 val2 val3 ...
VFill =  $43 ; args: len val
VMove =  $44 ; args: len addrh addrl
VPace =  $45 ; stop drawing until next frame

.segment "ZEROPAGE" ; $0-ff indices into the queue:
VHead:   .res 1 ; 1) main appends commands here.
VCommit: .res 1 ; 2) main moves this fwd to publish to nmi.
VTail:   .res 1 ; 3) nmi interprets and moves fwd.
; conceptually tail <= commit <= head, though since they
; wrap in memory that won't usually be literally true.

.segment "ZEROPAGE" ; nmi/main communication:
VCtrl:  .res 1 ; \ shadow registers. sent next draw, except
VMask:  .res 1 ; | VCtrl.7 ignored: nmi is kept enabled.
VSclX:  .res 1 ; | careful of data races. for synchronous
VSclY:  .res 1 ; / drawing: 0->VMask, vsync, inc Mutex.
V:      .res 3 ; draw scratch, can't touch W in nmi.
OamPg:  .res 1 ; if sprites enabled.
PalPg:  .res 1 ; 0 to skip, clears after upload.
Frames: .res 1 ; counter for synching or delaying.
Mutex:  .res 1 ; nonzero: nmi locked, plus draw tally.
; a degenerate draw queue eventually tallies to 128+,
; the draw interpreter abandons, nmi recovers. TODO xref

; https://www.nesdev.org/wiki/PPU_registers
PpuCtrl =   $2000 ; %n.tbsvyx nmi tall bgpat sprpat vert yxtbl
PpuMask =   $2001 ; %rgbsbllg dimrgb spr bg leftcol greysc
PpuStatus = $2002 ; %vho..... vblank 0hit overflow
OamAddr =   $2003 ; ppu write offset, nonzero corrupts oam!
PpuScroll = $2005 ; send x then y \ touch PpuStatus
PpuAddr =   $2006 ; addrh, addrl  / to reset order latch
PpuData =   $2007 ; increments by 1 or 32 (PpuCtrl vert)
OamDma =    $4014 ; (cpu) page to transfer to ppu

.segment "CODE"
draw: ; ~2240c left after nmi prologue
    _ lda #1, sta Mutex ; lock nmi for synch'd draw.
    ; reset PpuAddr/PpuScroll write latch only once(!):
    bit PpuStatus ; risky! a bug below will break drawing.
    ; load sprites:
    _ lda VMask, sta PpuMask ; bg/sprites on/off
    _ and #$10, beq :+ ; sprites disabled? -> skip dma
    _ lda #$00, sta OamAddr ; \ costs
    _ lda OamPg, sta OamDma ; / 521c
:   ; load palette:
    _ lda PalPg, beq :++ ; palette unchanged?
    _ ldy #$00, sta V+1, sty V, sty PalPg ; take ptr
    _ sty PpuCtrl ; horizontal mode
    _ lda #$3f, sta PpuAddr, sty PpuAddr ; $3f00-3f1f
:   lda (V),y   ; \ txfer     6c \ 17c * 32 = 544c
    sta PpuData ; / byte      4c | TODO unroll?
    _ iny, cpy #$20, bne :- ; 7c / +138 bytes -160 cycles
:   ; save pstack, interpret draw commands, advance tail:
    _ txa, pha, ldx VTail, jsr @horiz, stx VTail, pla, tax
    ; vblank is possibly blown. construct queues carefully!
    ; restore main's configured drawing mode, vblank willing:
    _ lda VCtrl, ora #$80, sta PpuCtrl
    ; https://www.nesdev.org/wiki/PPU_scrolling#Frequent_pitfalls
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
    _ sta PpuAddr, sty PpuAddr ; unlatched(!) to save 4c
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

DEF to_v, ">V" ; ( addr -- ) append address to queue.
    Lda H,x         ; queue expects big-endian!
    jsr a_to_v
DEF c_to_v, "C>V" ; ( c -- ) append byte to queue.
    lda L,x
    inx
a_to_v:
    ldy VHead
    sta VCmds,y
    iny             ; full page buffer, expects wraparound.
    sty VHead
    rts

DEF vcommit, "VCOMMIT" ; ( -- ) send queued draw commands.
    _ lda VHead, sta VCommit, rts

DEF vflush, "VFLUSH" ; ( -- ) wait for draw to finish.
    lda VCommit
    ; TODO degenerate case: malformed queue that defers often
    ; but overshoots VCommit and never finishes. could add a
    ; Frames check, or rely on nmi break key (also TODO).
:   cmp VTail       ; nmi will failsafe on a runaway queue.
    bne :-          ; it might take several frames though.
    rts

DEF voff, "VOFF" ; ( -- ) to draw directly.
    _ lda VMask, and #$e7, sta VMask ; render off
DEF vsync, "VSYNC" ; ( -- ) wait for next vblank.
    lda Frames
:   _ cmp Frames, beq :-
    rts

; TTY DRIVER ------------------------------------------------

.segment "RODATA"
RomPalette:
    .align 256
    .repeat 8
        .byte $0F, $29, $17, $20
    .endrepeat

.segment "ZEROPAGE" ; tty cursor:
CsrCol: .res 1 ; 0-31, width of screen.
CsrRow: .res 1 ; 0-253, except seam rows 30,31,62,63 etc
; vaddr calc drops CsrRow.6-7, so effectively 0-29,32-61.
; last two columns are in overscan caution zone.
; https://www.nesdev.org/wiki/Overscan

; nw ntb0 -> [ $2000-23ff ][ $2400-27ff ] <- ne ntb1  \ 1k
; sw ntb2 -> [ $2800-2bff ][ $2c00-2fff ] <- se ntb3  / each
;
; [^2] most carts map nametables 0-3 to the ppu internal 2k,
; mirroring either horizontally or vertically. ntb1 and 2 are
; contiguous in memory and pair with both configurations.

.segment "CODE"
DEF page, "PAGE" ; ( -- ) init and clear the screen.
    ; called on reset, must enable nmi directly! [^1]
    ; synchronous, ~0.6f.
    ; attempt to recover bad queue/mutex, very racey:
    _ lda VCommit, sta VTail, sta VHead ; delete the queue
    _ lda #$00, sta Mutex ; unlock nmi (paranoid)
    _ lda #$80, ora VCtrl, sta PpuCtrl ; [^1] enable nmi
    jsr voff
    _ lda #$00, sta CsrRow, sta CsrCol
    sta VSclY ; TODO compute from row
    _ lda #$f8, sta VSclX ; left edge inside overscan
    _ lda #>RomPalette, sta PalPg ; default palette
    _ stx W ; save pstack
    _ ldy #$24, lda #$00, bit PpuStatus, sty PpuAddr, sta PpuAddr
    _ ldy #$08, ldx #$00 ;lda #$00
:   stx PpuData ; TODO test pattern: stx, clear: sta
    _ inx, bne :- ; 256 bytes
    _ dey, bne :- ; 8 pages = nametables 1+2 $2400-2bff [^2]
    _ ldx W ; restore pstack
    _ lda #$0a, sta VMask ; bg on, sprites off
    rts

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

DEF rawemit, "RAWEMIT" ; ( c -- ) display a character.
    _ jsr csr_vaddr, inc CsrCol
    _ lda CsrCol, cmp #32, bcc :+ ; still on screen?
    jsr cr ; no: go to next line
:   _ lda #VSend, jsr a_to_v, lda #1, jsr a_to_v ; send one
    lda L,x                        ; stack-taken
    _ inx, jsr a_to_v, jmp vcommit ; character

DEF cr, "CR" ; ( -- ) move the cursor to the start of next line.
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

; MAIN ------------------------------------------------------

.segment "CODE"
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

_ DmcFreq = $4010, Joy1 = $4016, Joy2 = $4017

reset: ; just powered on, turn off all the things:
    _ sei, cld ; irq, decimal mode
    _ ldx #$40, stx Joy2 ; sound, and screen:
    _ ldx #$00, stx DmcFreq, stx PpuCtrl, stx PpuMask
    ; wait 2 frames for ppu, init ram in the meantime:
    bit PpuStatus
:   _ bit PpuStatus, bpl :- ; first frame
    ; banging the PpuStatus vblank bit risks a missed frame.
    ; needed for reset but runtime will track via Frames.
    lda #0
:   sta $000,x
    sta $100,x
    sta $200,x
    sta $300,x
    sta $400,x ; TODO (block buffer here? leave dirty?)
    sta $500,x
    sta $600,x
    sta $700,x
    _ inx, bne :-
:   _ bit PpuStatus, bpl :- ; second frame
    ; TODO init banks? keyboard? tty?
    _ ldx #$ff, txs, inx ; clear both forth stacks
    _ jsr page, jmp main ; clear bg, start nmi, start main

nmi: ; 2270c deadline to finish drawing
    _ bit Custom, bpl :+ ; default nmi service?
    jmp (Nmi) ; no, custom
:   _ pha, tya, pha ; subroutines responsible for x.
    _ lda Mutex, bne :+ ; re-entered?
    inc Frames ; notify main a vblank happened.
    jsr draw   ; store 1 in Mutex and process queue.
    ; TODO poll Joy1? scan kb? sound?
    _ lda #0, sta Mutex ; unlock next frame
:   _ pla, tay, pla, rti

irq:
    _ bit Custom, bvc :+
    jmp (Irq)
:   rti

.segment "RAMVEC" ; overrides:
Custom: .res 1 ; custom handlers: $80 nmi, $40 irq
Nmi:    .res 2 ; \ handler routine pointers. set Custom
Irq:    .res 2 ; / to 0 first to update atomically.

.segment "ROMVEC" ; in rom, required by the cpu:
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
