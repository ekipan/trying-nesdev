
; experiments and studies towards a family forth.
; just a noninteractive scrolling demo so far (TODO).
;
; to jump around, grep for:
; /code_label:/ /DEF forth_code_label/ /"FORTH-WORD"/
; /DataLabel:/ /ConstantLabel =/ /MACRO /

; MACROS ----------------------------------------------------

; time for a bad first impression! code *should* be dense:
.macro _ I,J,K,L,M,N ; list of instructions.
    .if .not .blank({I}) ; up to 6:
        I
        _ J,K,L,M,N
    .endif ; eg: _ pha, txa, pha, tya, pha
.endmacro  ; eg: _ jsr foo, jsr bar, jmp qux
; rule: 0/1 loads to start, 0/1 branches to end.
; *usually* avoid: rts, rti, jmp.

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
    .popseg ; back to original segment:
    XT:     ; where the code will follow.
.endmacro ; eg: foo: DEF "FOO" ; ( a -- b ) does foo.
; xt field first makes an nt a direct xt pointer.

; TODO write `find` then put these there
; Immediate = $80 ; flag: execute even in compile mode
; NeverTco =  $40 ; flag: never tail-call-optimize into a jmp
; Hidden =    $20 ; flag: skipped by find
; Length =    $1f ; mask: up to 31 character names

.macro CONSTANT LABEL_EQ, VALUE ; push value to pstack.
    lda #<VALUE
    ldy #>VALUE
    jmp push_ya
    LABEL_EQ VALUE
.endmacro ; eg: ; DEF foo, "FOO" ; CONSTANT Foo =, 123
; integrated "=" is weird but greppable. TODO optimize byte?

.macro CVALUE ADDR ; fetch unsigned byte value from ram.
    lda abs:ADDR
    jmp push_a
.endmacro ; wasted abs byte for runtime to store through.

.macro VALUE ADDR ; fetch cell value from ram.
    ldy abs:ADDR+1
    lda ADDR
    jmp push_ya
.endmacro ; runtime can detect size by first opcode.

; CORE ------------------------------------------------------

.segment "PSTACK": zp ; to lay at 0 for aesthetics.
     .res 32 ; usual convention: y: [H], a: [L], x: index.
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

lit: ; ( -- n ) fetch through return address.
    ; TODO lit
push_ya: ; ( -- y:a )
    dex
put_ya: ; ( ? -- y:a )
    sty H,x
    sta L,x
    rts

; forth flags, to be branched to from testing words:

DEF neg_one, "-1" ; ( -- -1 )
    lda #$ff
push_neg_a:
    dex
put_neg_a:
    ldy #$ff
    sty H,x
    sta L,x
    rts

DEF zero, "0" ; ( -- 0 )
    lda #0
push_a: ; ( -- 0:a )
    dex
put_a: ; ( ? -- 0:a )
    ldy #0
    sty H,x
    sta L,x
    rts

; DRAW COMMANDS QUEUE ---------------------------------------

; the picture processing unit rejects i/o while drawing the
; screen, draw commands must be sent during 2270c vblank, so
; I encode them into a ring buffer to send asynchronously.

.segment "QUEUE"
     .align 256 ; page-aligned so indices wrap.
VCmds: .res 256 ; encoded drawing commands queue.

.segment "ZEROPAGE" ; $0-ff indices into the queue:
VHead:   .res 1 ; 1) main appends commands here.
VCommit: .res 1 ; 2) main moves this fwd to publish to nmi.
VTail:   .res 1 ; 3) nmi interprets and moves fwd.
; conceptually tail <= commit <= head, though since they
; wrap in memory that won't usually be literally true.

.segment "CODE"
DEF to_v, ">V" ; ( addr -- ) append address to queue.
    Lda H,x         ; queue expects big-endian!
    jsr v_a
DEF c_to_v, "C>V" ; ( c -- ) append byte to queue.
    lda L,x
    inx
v_a:
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
    ; but overshoots VCommit and never finishes. could add an
    ; NmiFrames check, or rely on nmi break key (also TODO).
:   cmp VTail       ; nmi will failsafe on a runaway queue.
    bne :-          ; it might take several frames though.
    rts

VImmediate =  $80 ; args: len val1 val2 val3 ...
VFill =       $81 ; args: len val
VTransfer =   $82 ; args: len addrh addrl
VHorizontal = $83 ; \ set PpuCtrl
VVertical =   $84 ; / direction bit
VEnd =        $85 ; stop drawing until next frame

; NMI -------------------------------------------------------

.segment "ZEROPAGE" ; main shouldn't touch these!
NmiBusy: .res 1 ; reentry and runaway queue guard.
NmiW:    .res 3 ; scratch: 2b ptr 1b len.

.segment "ZEROPAGE" ; nmi/main communication:
NmiFrames:  .res 1 ; counter for synching or delaying.
NmiDma:     .res 1 ; page to dma from if enabled.
NmiPalette: .res 1 ; page to copy from, or 0 if unchanged.
NmiCtrl:    .res 1 ; \ shadow registers, main updates
NmiMask:    .res 1 ; | will show up next frame so
NmiScrollX: .res 1 ; | there's a risk of data races.
NmiScrollY: .res 1 ; / avoid intermediates.

DmcFreq =   $4010 ; https://www.nesdev.org/wiki/2A03#-overview
OamDma =    $4014 ; https://www.nesdev.org/wiki/APU#-bitfields
Joy1 =      $4016 ; https://www.nesdev.org/wiki/PPU
Joy2 =      $4017 ; (seems a good place to put these:)
PpuCtrl =   $2000 ; %n0tbsvyx nmi tall bgpat sprpat vert yxtbl
PpuMask =   $2001 ; %rgbsbllg dimrgb spr bg leftcol grey
PpuStatus = $2002 ; %vho00000 vblank? 0hit? overflow?
OamAddr =   $2003 ; ppu offset to start write, wraps
PpuScroll = $2005 ; send x then y
PpuAddr =   $2006 ; latch, then send addrh, addrl
PpuData =   $2007 ; increments by 1 or 32 (PpuCtrl vert)

.segment "CODE" ; service a nonmaskable interrupt.
DEF vblank, "VBLANK" ; ( -- ) wait for next vblank.
    lda NmiFrames
:   _ cmp NmiFrames, beq :-
    rts

nmi: ; 2270c deadline to finish drawing
    _ bit Custom, bpl :+ ; default nmi service?
    jmp (Nmi)       ; no, custom
:   _ pha, lda NmiBusy, beq @default_service ; unlocked?
    _ pla, rti      ; no, leave re-entered nmi
@default_service:
    _ txa, pha, tya, pha
    _ inc NmiFrames, inc NmiBusy ; 1 service, n draw commands
    _ lda NmiCtrl, ora #$80, sta PpuCtrl ; nmi always on!
    ; load sprites:
    _ lda NmiMask, sta PpuMask ; bg/sprites on/off
    _ and #$10, beq :+ ; sprites disabled? -> skip dma
    _ lda #$00, sta OamAddr  ; \ costs
    _ lda NmiDma, sta OamDma ; / 521c
:   ; load palette:
    _ lda NmiPalette, beq :++ ; palette unchanged?
    _ ldy #$00, sta NmiW+1, sty NmiW, sty NmiPalette
    _ lda #$3f, sta PpuAddr, sty PpuAddr
:   lda (NmiW),y ; \ txfer    5c \ 16c * 32 = 512c
    sta PpuData  ; / byte     4c | TODO unroll?
    _ iny, cpy #$20, bne :- ; 7c / +138 bytes -160 cycles
:   ; interpret draw commands and move tail forward:
    _ ldx VTail, jsr @interpret_ring, stx VTail
    bit PpuStatus ; reset latch for:
    ; https://www.nesdev.org/wiki/PPU_scrolling#Frequent_pitfalls
    _ lda NmiScrollX, sta PpuScroll ; must scroll after
    _ lda NmiScrollY, sta PpuScroll ; PpuAddr writes
    ; TODO poll joypad, scan kb?
    _ lda #0, sta NmiBusy ; unlock next frame
    _ pla, tay, pla, tax, pla, rti

; entrypoint in the middle for branch range reasons:

@horizontal: ; incrmode bit clear (+1)
    _ lda #$fb, and NmiCtrl, sta NmiCtrl, sta PpuCtrl
    jmp @loop
@vertical: ; incrmode bit set (+32)
    _ lda #$04, ora NmiCtrl, sta NmiCtrl, sta PpuCtrl
    jmp @loop
@immediate: ; (x)y=len val1 val2 val3 ...
:   inx
    lda VCmds,x     ; val#
    _ sta PpuData, dey, bne :-
    beq @inx_and_loop
; most common command, to fallthru into @loop:
@set_addr: ; a=$hh (x)y=$ll
    _ bit PpuStatus, sta PpuAddr, sty PpuAddr
  @inx_and_loop:
    inx
  @loop:
    inc NmiBusy     ; tally one command finished
    bmi @abandon    ; >127? probably a runaway queue
  @interpret_ring: ; x = cursor into page-aligned ring buffer
    _ cpx VCommit, beq @rts ; no work left to do?
    ; command bytes:  (x)opcode (arg1 arg2 ...)
    lda VCmds,x     ; (x)a=opcode (arg1 ...)
    inx             ; a=opcode (x)(arg1 ...)
    ldy VCmds,x     ; a=opcode (x)y=(arg1) (...)
    _ cmp #$40, bcc @set_addr ; $0-3f, valid ppu page?
    _ cmp #VTransfer, beq @transfer
    _ cmp #VFill, beq @fill
    _ cmp #VImmediate, beq @immediate
    _ cmp #VHorizontal, beq @horizontal
    _ cmp #VVertical, beq @vertical
    _ cmp #VEnd, beq @rts ; end frame: defer to next nmi
  @abandon: ; malformed command (or runaway queue).
    ldx VCommit
  @rts:
    rts
@fill: ; (x)y=len val
    inx
    lda VCmds,x     ; val
:   _ sta PpuData, dey, bne :-
    beq @inx_and_loop
@transfer: ; (x)y=len $hh $ll
    sty NmiW+2      ; len
    inx
    lda VCmds,x     ; $hh
    sta NmiW+1      ; read addr high
    inx
    lda VCmds,x     ; $ll
    sta NmiW        ; read addr low
    ldy #0          ; scan fwd from 0 to len:
:   lda (NmiW),y
    _ sta PpuData, iny, cpy NmiW+2, bne :-
    beq @inx_and_loop
    rts ; (unnecessary, for the debugger)

; RESET, MAIN -----------------------------------------------

.segment "ROMVEC" ; in rom, required by the cpu:
    .addr nmi   ; at vblank
    .addr reset ; at power on and reset
    .addr irq   ; unused by default

.segment "RAMVEC" ; overrides:
Custom: .res 1 ; custom handlers: $80 nmi, $40 irq
Nmi:    .res 2 ; \ handler routine pointers. set Custom
Irq:    .res 2 ; / to 0 first to update atomically.

.segment "CODE"
irq:
    _ bit Custom, bvc :+
    jmp (Irq)
:   rti

reset: ; just powered on, turn off all the things:
    _ sei, cld
    _ ldx #$40, stx Joy2 ; sound, and screen:
    _ ldx #$00, stx DmcFreq, stx PpuCtrl, stx PpuMask
    ; wait 2 frames for ppu, init ram in the meantime:
    bit PpuStatus
:   _ bit PpuStatus, bpl :- ; first frame
    lda #0
:   sta $000,x
    sta $100,x
    sta $200,x
    sta $300,x
    sta $400,x      ; TODO (block buffer here? leave dirty?)
    sta $500,x
    sta $600,x
    sta $700,x
    _ inx, bne :-
:   _ bit PpuStatus, bpl :- ; second frame
    ; TODO init banks? keyboard? tty?
    ; clear background:
    _ ldy #$20, lda #$00
    _ bit PpuStatus, sty PpuAddr, sta PpuAddr
    ldy #$10        ; all 4 nametables, for any mapper
:   stx PpuData     ; TODO sta ' ', stx 'abc', sty page
    _ inx, bne :-
    _ dey, bne :-
abort:
    ldx #0          ; empty pstack
quit:
    _ txa, ldx #$ff, txs, tax  ; empty rstack
    _ lda #>RomPalette, sta NmiPalette ; default palette
    _ lda #$0a, sta NmiMask    ; bg on, sprites off
    _ lda #$f8, sta NmiScrollX ; left edge inside overscan
    _ lda #$00, sta NmiBusy    ; unlock nmi and:
    _ lda #$80, sta NmiCtrl, sta PpuCtrl ; enable
main: ; ready to go.
    jsr vblank      ; wait one frame
    lda #1 ; pixel
    clc
    adc NmiScrollY  ; scroll up
    tay
    cmp #$f0
    bcc :+          ; not between screens?
    sbc #$f0        ; a = a-240-(1-c)
    tay
    lda #2
    eor NmiCtrl
    sta NmiCtrl    ; flip ntbl \ data
:   sty NmiScrollY ;           / race 3c
    jmp main

.segment "RODATA"
RomPalette:
    .align 256
    .repeat 8
        .byte $0F, $29, $17, $20
    .endrepeat

; nes cartridge configurations vary wildly. emulators support
; a huge range, but I still need to study the constraints of
; a feasibly realizable cart (TODO). I'm not very interested
; in making one but I'd like it to be possible.
;
; one scratch prg-ram bank: oam? drawqueue? blockbuffer?
; the rest to compile user code and dictionary entries into.
; nes powerdown risks prg-ram corruption via random
; instructions. fine for scratch.
;
; in lieu of studying the tape recorder (TODO), I'd wish for
; extra prg-ram banks to store user source code and data
; blocks long term. risk of rogue bank-switch then corruption
; is probably astronomical. would be curious.

; cart config: https://www.nesdev.org/wiki/Mapper
Mapper =  1 ; $s0mm: w/ sub. 0 nrom, 1 mmc1, 218 nesmon's
HMirror = 1 ; 0/1: vert/horiz, opposite scroll dir
PrgRoms = 2 ; $nn:  16k banks at cpu $8000-ffff
PrgRams = 1 ; $nn:   8k banks at cpu $6000-7fff, w/ battery
ChrRoms = 1 ; $nn: \ 8k banks on ppu bus
ChrRams = 0 ; $nn: / usually one or the other
Periph =  0 ; $0-4f: 0 none, $23 basic keyboard

.segment "INES" ; binfmt: https://www.nesdev.org/wiki/NES_2.0
    .byte "NES", $1a, PrgRoms&255, ChrRoms&255 ; 0-5
    .byte ((Mapper&$f)<<4) | ((PrgRams>0)<<1) | HMirror ; 6
    .byte ((Mapper>>4)&$f) | 8 ; 7 nes hw, nes format 2.0
    .byte (Mapper>>8), 0, PrgRams, ChrRams, 0, 0, 0, Periph
