
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
; *mostly* avoid: rts, rti, jmp.

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
; xt field first makes an nt a direct xt pointer: >XT = @

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
NmiBusy: .res 1 ; reentry mutex and runaway queue guard.
NmiW:    .res 3 ; scratch: 2b ptr 1b len.

.segment "ZEROPAGE" ; nmi/main communication:
NmiFrames:  .res 1 ; counter for synching or delaying.
NmiOamPg:   .res 1 ; if sprites enabled.
NmiPalPg:   .res 1 ; 0 to skip, clears after upload.
NmiCtrl:    .res 1 ; \ shadow registers.
NmiMask:    .res 1 ; | updates show up next
NmiScrollX: .res 1 ; | frame, risk of data
NmiScrollY: .res 1 ; / races.

DmcFreq =   $4010
OamDma =    $4014
Joy1 =      $4016
Joy2 =      $4017
; https://www.nesdev.org/wiki/PPU_registers
PpuCtrl =   $2000 ; %n-tbsvyx nmi tall bgpat sprpat vert yxtbl
PpuMask =   $2001 ; %rgbsbllg dimrgb spr bg leftcol greysc
PpuStatus = $2002 ; %vho----- vblank 0hit overflow
OamAddr =   $2003 ; ppu write offset, nonzero corrupts oam!
PpuScroll = $2005 ; send x then y \ touch PpuStatus
PpuAddr =   $2006 ; addrh, addrl  / to reset order latch
PpuData =   $2007 ; increments by 1 or 32 (PpuCtrl vert)

.segment "CODE" ; service a nonmaskable interrupt.
nmi: ; 2270c deadline to finish drawing
    _ bit Custom, bpl :+ ; default nmi service?
    jmp (Nmi)       ; no, custom
:   _ pha, lda NmiBusy, beq @default_service ; unlocked?
    _ pla, rti      ; no, leave re-entered nmi
@default_service:
    _ txa, pha, tya, pha
    ; reset PpuAddr/PpuScroll write latch only once(!):
    bit PpuStatus ; risky! a bug below will break drawing.
    ; load sprites:
    _ lda NmiMask, sta PpuMask ; bg/sprites on/off
    _ and #$10, beq :+ ; sprites disabled? -> skip dma
    _ lda #$00, sta OamAddr    ; \ costs
    _ lda NmiOamPg, sta OamDma ; / 521c
:   ; load palette:
    _ lda NmiPalPg, beq :++ ; palette unchanged?
    _ ldy #$00, sta NmiW+1, sty NmiW, sty NmiPalPg ; take ptr
    _ sty PpuCtrl ; horizontal mode
    _ lda #$3f, sta PpuAddr, sty PpuAddr ; $3f00-3f1f
:   lda (NmiW),y ; \ txfer    5c \ 16c * 32 = 512c
    sta PpuData  ; / byte     4c | TODO unroll?
    _ iny, cpy #$20, bne :- ; 7c / +138 bytes -160 cycles
:   ; configure while we still have time:
    inc NmiFrames ; notify main a vblank happened.
    inc NmiBusy   ; defensively lock against nmi re-entry.
    ; nmi always enabled, start drawing in horizontal mode:
    _ lda NmiCtrl, ora #$80, and #$fb, sta PpuCtrl
    ; interpret draw commands and move tail forward:
    _ ldx VTail, jsr @interpret_ring, stx VTail
    ; vblank is possibly blown. construct queues carefully!
    ; restore main's configured drawing mode, vblank willing:
    _ lda NmiCtrl, ora #$80, sta PpuCtrl
    ; https://www.nesdev.org/wiki/PPU_scrolling#Frequent_pitfalls
    _ lda NmiScrollX, sta PpuScroll ; shares PpuAddr register,
    _ lda NmiScrollY, sta PpuScroll ; must set *after* draw.
    ; TODO poll joypad? scan kb? sound?
    _ lda #0, sta NmiBusy ; unlock next frame
    _ pla, tay, pla, tax, pla, rti

; entrypoint in the middle for branch range reasons:

@horizontal: ; incrmode bit clear (+1), default per frame
    _ lda NmiCtrl, ora #$80, and #$fb, sta PpuCtrl
    jmp @loop
@vertical: ; incrmode bit set (+32)
    _ lda NmiCtrl, ora #$84, sta PpuCtrl
    jmp @loop
@immediate: ; (x)y=len val1 val2 val3 ...
:   inx
    lda VCmds,x     ; val#
    _ sta PpuData, dey, bne :-
    beq @inx_and_loop
; most common command, to fallthru into @loop:
@set_addr: ; a=$hh (x)y=$ll
    _ sta PpuAddr, sty PpuAddr ; unlatched(!) to save 4c
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
    ; in order of likeliness, to squeeze cycles:
    _ cmp #$40, bcc @set_addr ; $0-3f, valid ppu page?
    _ cmp #VImmediate, beq @immediate ; workhorse draw
    _ cmp #VFill, beq @fill         ; clearing/blocking out
    _ cmp #VEnd, beq @rts           ; frame pacing
    _ cmp #VTransfer, beq @transfer ; usually during setup
    _ cmp #VVertical, beq @vertical ; switch to columns
    _ cmp #VHorizontal, beq @horizontal ; back to default
    ; malformed command.
  @abandon:
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

DEF voff, "VOFF" ; ( -- ) to draw directly.
    _ lda NmiMask, and #$e7, sta NmiMask ; render off
DEF vsync, "VSYNC" ; ( -- ) wait for next vblank.
    lda NmiFrames
:   _ cmp NmiFrames, beq :-
    rts

; terminal primitives:

.segment "ZEROPAGE"
CsrRow: .res 1
CsrCol: .res 1

.segment "CODE"
DEF page, "PAGE" ; ( -- ) init and clear the screen.
    ; called on reset, must enable nmi directly! [^1]
    ; synchronous, ~0.6f.
    ; attempt to recover bad queue/mutex, very racey:
    _ lda #$00, sta NmiBusy ; unlock nmi (paranoid)
    _ lda VCommit, sta VTail, sta VHead ; delete the queue
    _ lda #$80, ora NmiCtrl, sta PpuCtrl ; [^1] enable nmi
    jsr voff
    _ lda #$00, sta CsrRow, sta CsrCol
    sta NmiScrollY ; TODO compute from row
    _ lda #$f8, sta NmiScrollX ; left edge inside overscan
    _ lda #>RomPalette, sta NmiPalPg ; default palette
    _ txa, pha ; save pstack
    _ ldy #$24, lda #$00, bit PpuStatus, sty PpuAddr, sta PpuAddr
    _ ldy #$08, ldx #$00 ;lda #$00
:   stx PpuData ; TODO test pattern: stx, clear: sta
    _ inx, bne :- ; 256 bytes
    _ dey, bne :- ; 8 pages = nametables 1+2 $2400-2bff [^2]
    _ pla, tax ; restore pstack
    _ lda #$0a, sta NmiMask ; bg on, sprites off
    rts

;  nw ntb0 -> [ $2000-23ff ][ $2400-27ff ] <- ne ntb1  \ 1k
;  sw ntb2 -> [ $2800-2bff ][ $2c00-2fff ] <- se ntb3  / each
;
; [^2] most carts map nametables 0-3 to the ppu internal 2k,
; mirroring either horizontally or vertically. ntb1 and 2 are
; continguous in memory and pair with both configurations.

DEF cr, "CR" ; ( -- ) move the cursor to the start of next line.
    _ lda #VEnd, jsr a_to_v ; flush pending draws.
    _ lda #$00, sta CsrCol ; col = 0, increment row:
    _ ldy CsrRow, jsr @iny, sty CsrRow, jsr @clear ; and clear.
    _ ldy CsrRow, jsr @iny, jsr @clear ; and below screen.
    ; TODO scroll.
    jmp vcommit
@iny:
    _ iny, tya, and #31, cmp #30, bcc :+ ; still in-screen?
    _ iny, iny ; pass over attrtable seam.
:   rts
@clear: ; TODO extract cursor compute from this for 'page'
    _ lda #$00, sta W ; compute: $2400 + (y & 63) << 5
    _ tya, asl, asl, asl, rol W
    _ asl, rol W, asl, rol W
    _ ldy W, jsr push_ya ; ( offset )
    _ ldy #$24, lda #$00, jsr push_ya, ; ( offset base )
    _ jsr plus, jsr to_v     ; at row address:
    _ lda #VFill, jsr a_to_v ; fill
    _ lda #32, jsr a_to_v    ; an entire row
    _ lda #' ', jmp a_to_v   ; with spaces

.segment "RODATA"
RomPalette:
    .align 256
    .repeat 8
        .byte $0F, $29, $17, $20
    .endrepeat

; RESET, MAIN -----------------------------------------------

.segment "CODE"
reset: ; just powered on, turn off all the things:
    _ sei, cld
    _ ldx #$40, stx Joy2 ; sound, and screen:
    _ ldx #$00, stx DmcFreq, stx PpuCtrl, stx PpuMask
    ; wait 2 frames for ppu, init ram in the meantime:
    bit PpuStatus
:   _ bit PpuStatus, bpl :- ; first frame
    ; banging the PpuStatus vblank bit risks a missed frame.
    ; needed for reset but runtime will track via NmiFrames.
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
    _ ldx #$ff, txs, inx ; clear both forth stacks
    jsr page        ; clear background and start nmi.
main:
    lda #1 ; pixel
    jsr add_y
    jsr vsync       ; wait one frame
    jmp main

add_y: ; y += a, [-16..16] for correct seam jump.
    clc
    adc NmiScrollY
    tay
    cmp #$f0
    bcc :+          ; not between screens?
    sbc #$f0        ; a = a-240-(1-c)
    tay
    lda #2
    eor NmiCtrl
    sta NmiCtrl    ; flip ntbl \ data
:   sty NmiScrollY ;           / race 3c
    rts

.segment "CODE"
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
