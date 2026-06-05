
; experiments and studies towards a family forth.
;
; june 2026: forth structure is in progress but
;   main is just a noninteractive scrolling demo.
;   I'm avoiding the kb and tty drivers :/
;   drawlist interpreter was fun to write though!

; MACROS ----------------------------------------------------

; time to make a bad first impression!
.macro DO I,J,K,L,M,N,O,P,Q,R ; list of instructions.
    .if .not .blank({I})
        I ; supports .byte .word, but no ixns with a comma.
        DO J,K,L,M,N,O,P,Q,R ; up to 10.
    .endif ; eg: DO pha, txa, pha, tya, pha
.endmacro  ; eg: DO jsr foo, jsr bar, jmp qux
; god I hate boilerplate. code *should be dense*.

; inserted `bit` opcodes overlap and skip next instruction:
.define JMP1 .byte $24 ; bit zp  ; 1 operand byte
.define JMP2 .byte $2C ; bit abs ; 2 operand bytes
; to save versus a jmp over another entrypoint.

; wordlist contiguous through RAM/ROM boundary at $8000.
; assembles up into ROM, runtime prepends down into RAM.
; `find` scans fwd until a `0` XT after the last ROM word.

.macro DEF NAME, FLAGS ; assemble an entry into DICT ROM.
    .local XT, LEN
    LEN = (FLAGS+0) | .strlen(NAME) ; blank FLAGS needs +0.
    .pushseg
    .segment "DICT" ; a nametoken (nt) is an entry address:
        .addr XT        ; execution token is a code address
        .byte LEN, NAME ; flags, length, characters
    .popseg ; back to original segment:
    XT = *  ; where the code will follow.
.endmacro ; eg: foo: DEF "FOO" ; ( a -- b ) does foo.

Immediate = $80 ; flag: execute even in compile mode
NeverTco  = $40 ; flag: never tail-call-optimize into a `jmp`
Hidden    = $20 ; flag: skipped by `find`
Length    = $1f ; mask: up to 31 character names

.macro DEFCONST NAME, VALUE ; ( -- value )
    DEF NAME
    ldy #>VALUE ; msb first to ease runtime compile:
    lda #<VALUE ; : constant ( n "name" -- ) ...
    jmp push_ya ;   split ( lsb msb ) ldy #, lda #, ... ;
.endmacro ; TODO revisit ldy/a order after writing compiler.

.macro DEFVALUE NAME, ADDR ; ( -- n ) fetch from RAM.
    DEF NAME
    lda abs:ADDR ; possibly waste a byte on absolute
    ldy ADDR+1   ;  addressing, makes uniform to ease
    jmp push_ya  ;  storing through a higher-level (TO).
.endmacro ; TODO needed? maybe a smarter compiler instead.

; CORE ------------------------------------------------------

.segment "PSTACK": zp ; to lay at 0 for aesthetics.
     .res 32
L:   .res 32 ; \ split parameter stack to pass data b/n words.
H:           ; / x-indexed, growing downwards from x=$ff.
W:   .res 2  ; then six bytes of scratch, including:
Dst: .res 2  ; \ load/store
Src: .res 2  ; / pointers.

.segment "CODE"
store: DEF "!" ; ( n addr -- ) store n at addr.
    lda L,x
    ldy H,x
    inx             ; drop addr
store_ya: ; ( n [y:a] -- ) store through addr in registers.
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

fetch: DEF "@" ; ( addr -- n ) fetch n from addr.
    lda L,x
    ldy H,x
    JMP1
fetch_ya: ; ( [y:a] -- n ) from register address.
    dex
    sta Src
    sty Src+1
    ldy #0
    lda (Src),y
    sta L,x
    lda (Src+1),y
    sta H,x
    rts

c_store: DEF "C!" ; ( c addr -- ) store c at addr.
    lda L+0,x       ; L: ..[ll]cc   H:  .. hh 00
    sta H-1,x       ;    .. ll cc      [ll]hh 00
    lda L+1,x       ;    .. ll[cc]      ll hh 00
    sta (H-1,x)     ;    .. ll cc      [ll hh]00
    DO inx, inx     ; ( c addr ) 2drop
    rts

c_fetch: DEF "C@" ; ( addr -- c ) fetch c from addr.
    lda L+0,x       ; L: ..[ll]   H:  .. hh
    sta H-1,x       ;    .. ll       [ll]hh
    lda (H-1,x)     ;    .. ll       [ll hh]
    jmp put_unsigned_a

two_plus: DEF "2+" ; ( n -- n+2 ) add 2.
    inc L,x
    bne one_plus
    inc H,x
one_plus: DEF "1+" ; ( n -- n+1 ) add 1.
    inc L,x
    bne :+
    inc H,x
:   rts

lit: ; ( -- n ) fetch through return address.
    ; TODO lit
push_ya: ; ( -- [ya] )
    dex
put_ya: ; ( x -- [ya] )
    sty H,x
    sta L,x
    rts

zero: DEF "0" ; ( -- 0 )
    lda #0
push_unsigned_a: ; ( -- [0a] )
    dex
put_unsigned_a: ; ( x -- [0a] )
    ldy #0
    sty H,x
    sta L,x
    rts

neg_one: DEF "-1" ; ( -- -1 )
    lda #$ff
    tay
    jmp :+
push_signed_a:
    dex
put_signed_a:
    ldy #0
    cmp #0
    bpl :+
    dey
:   sty H,x
    sta L,x
    rts

; INES HEADER, RESET ----------------------------------------

; nes cartridge configurations vary wildly. emulators support
; a huge range but I still need to study the constraints of
; making a feasibly realizable cart (TODO).
;
; in lieu of studying the tape recorder (TODO), I'd like a
; hefty portion of battery ram for long term user storage,
; mostly of typed-in forth source code.

; cart config: https://www.nesdev.org/wiki/Mapper
Mapper  = 1 ; $s0mm: w/ sub. 0 nrom, 1 mmc1, 218 nesmon's
HMirror = 1 ; 0/1: vert/horiz, opposite scroll dir
PrgRoms = 2 ; $nn:  16k banks at cpu $8000-ffff
PrgRams = 1 ; $nn:   8k banks at cpu $6000-7fff, w/ battery
ChrRoms = 1 ; $nn: \ 8k banks on ppu bus
ChrRams = 0 ; $nn: / usually one or the other
Periph  = 0 ; $0-4f: 0 none, $23 basic keyboard

.segment "INES" ; binfmt: https://www.nesdev.org/wiki/NES_2.0
    .byte "NES", $1a, PrgRoms&255, ChrRoms&255 ; 0-5
    .byte ((Mapper&$f)<<4) | ((PrgRams>0)<<1) | HMirror ; 6
    .byte ((Mapper>>4)&$f) | 8 ; 7 nes hw, nes format 2.0
    .byte (Mapper>>8), 0, PrgRams, ChrRams, 0, 0, 0, Periph

DmcFreq   = $4010 ; https://www.nesdev.org/wiki/2A03
OamDma    = $4014 ; https://www.nesdev.org/wiki/APU
Joy1      = $4016
Joy2      = $4017
PpuCtrl   = $2000 ; https://www.nesdev.org/wiki/PPU
PpuMask   = $2001
PpuStatus = $2002
OamAddr   = $2003
PpuScroll = $2005
PpuAddr   = $2006
PpuData   = $2007

.segment "CODE"
reset: ; just powered on, turn off all the things:
    sei             ; irq off
    cld             ; decimal off
    ldx #$40
    stx Joy2        ; sound counter irq off
    ldx #$ff        ; from the top:
    txs ; $ff       ;   of page 1, rstack grows down
    inx ; 0
    stx DmcFreq     ; sound irq off
    stx PpuCtrl     ; picture nmi off
    stx PpuMask     ; picture render off
    ; wait 2 frames for ppu, init ram in the meantime:
    bit PpuStatus
:   bit PpuStatus   ; first frame
    bpl :-
:   lda #$ff        ; offscreen, break commands:
    sta $200,x      ;   for sprites, QDraw
    lda #0          ; clear:
    sta $000,x      ;   pstack, variables
    sta $100,x      ;   rstack
    sta $300,x      ;   buffers, variables
    inx             ;   (4-7 block buffer left dirty, the
    bne :-          ;    user can clear or recover it)
:   bit PpuStatus   ; second frame
    bpl :-
    ; TODO init banks? keyboard? tty?
    stx OamAddr     ; offset 0 within:
    ldx #2          ; page 2
    stx OamDma      ; init sprites to offscreen
    jmp warm

.segment "ROMVEC" ; in rom, required by the cpu
    .addr nmi   ; at vblank
    .addr reset ; at power on and reset
    .addr irq   ; unused by default

.segment "RAMVEC" ; ram vector overrides
Vecs: .res 5 ; 0.7,6 enable custom nmi 2:1, irq 4:3
; customizing: (1) 0 -> Vecs, (2) new service addr
;   -> Vecs+(1..4), (3) $80/40/c0 -> Vecs.

.segment "CODE"
irq:
    bit Vecs        ; check control bits
    bvs :+          ; custom irq (Vecs.6 = 1)?
    rti
:   jmp (Vecs+3)

; DRAW COMMANDS QUEUE ---------------------------------------

; the picture processing unit rejects i/o while drawing the
; screen, they must be sent during 2273c vblank, so I encode
; draw commands into a ring buffer to send asynchronously.

.segment "QUEUE"
     .align 256 ; page-aligned so indices wrap.
QDraw: .res 256 ; encoded drawing commands queue.

.segment "ZEROPAGE" ; 0-255 indices into the queue:
QTail:   .res 1 ; nmi: to read and interpret
QCommit: .res 1 ; main: to publish to nmi
QHead:   .res 1 ; main: to append commands

; main: append commands to Head, move Commit forward.
; nmi: interpret Tail..Commit, move Tail forward.

.segment "CODE"
q_commit: DEF "Q-COMMIT" ; ( -- ) send queued draw commands.
    lda QHead
    sta QCommit
    rts

q_flush: DEF "Q-FLUSH" ; ( -- ) wait for draw to finish.
    lda QCommit
:   cmp QTail
    bne :-          ; nmi will failsafe on runaway queue.
    rts             ; it might take several frames though.

c_to_q: DEF "C>Q" ; ( c -- ) append byte to queue.
    lda L,x
    inx
q_a:
    ldy QHead
    sta QDraw,y
    iny             ; full page buffer, expects wraparound.
    sty QHead
    rts

to_q: DEF ">Q" ; ( a -- ) append address to queue.
    lda L,x
    Ldy H,x
    inx
q_ya: ; queue expects big-endian!
    DO pha, tya, jsr q_a, pla, jmp q_a

; refer to nmi for the actual draw commands interpreter.

QImmediate  = $80 ; len val1 val2 val3 ...
q_immediate: DEF "Q-IMMEDIATE" ; ( addr len -- ) send bytes.
    DO inx, inx, brk, rts ; TODO

QFill = $81 ; len val
q_fill: DEF "Q-FILL" ; ( c len -- ) fill bytes.
    DO lda #QFill, jsr q_a
    DO inx, inx, brk, rts ; TODO

QTransfer   = $82 ; len addrh addrl
QHorizontal = $83 ; ; \ set PpuCtrl
QVertical   = $84 ; ; / direction bit

QClear      = $85 ; ; temporarily disable PpuMask, then zap
q_clear: DEF "Q-CLEAR" ; ( -- ) clear screen.
    DO lda #QClear, jmp q_a

QBreak      = $FF ; ; defer rest of queue to next nmi
q_break: DEF "Q-BREAK" ; ( -- ) finish a frame.
    DO lda #QBreak, jmp q_a

; NMI -------------------------------------------------------

.segment "ZEROPAGE" ; nmi/main communication:
NmiFrames:  .res 1 ; counter for synching or delaying.
NmiOam:     .res 1 ; page to dma from, or 0 if disabled.
NmiCtrl:    .res 1 ; \  shadow registers, main updates
NmiMask:    .res 1 ;  | will show up next frame so be
NmiScrollX: .res 1 ;  | careful not to store intermediate
NmiScrollY: .res 1 ; /  values.
; PpuAddr and PpuData are controlled by QDraw.

.segment "ZEROPAGE" ; main should never touch these!
NmiBusy: .res 1 ; reentry and runaway queue guard.
NmiW:    .res 3 ; scratch.

.segment "CODE" ; service a nonmaskable interrupt.
:   jmp (Vecs+1)    ; custom nmi
:   pla             ; leave re-entered nmi
    rti
nmi: ; deadline of 2273c to draw
    bit Vecs
    bmi :--         ; custom nmi (Vecs.7 = 1)?
    pha
    lda NmiBusy
    bne :-          ; already working?
    DO txa, pha, tya, pha
    inc NmiBusy     ; one per draw queue command
    inc NmiFrames   ; one per nmi service
    ; send shadow registers and oam to ppu
    DO lda NmiCtrl, sta PpuCtrl
    DO lda NmiMask, sta PpuMask
    DO lda NmiScrollX, sta PpuScroll
    DO lda NmiScrollY, sta PpuScroll
    lda NmiOam      ; page to pull sprites from
    beq :+          ; disabled (0)?
    ldx #0          ; start of page:
    stx OamAddr     ;   ppu offset to write from, wraps.
    sta OamDma      ; 514c, but neglect will corrupt.
:   ; now start the draw command interpreter:
    ldx QTail       ; x = cursor into page-aligned ring buffer
@interpret:
        cpx QCommit
        beq @leave      ; done with queue work?
        ; command bytes: (x)opcode (arg1 arg2 ...)
        lda QDraw,x     ; (x)a=opcode (arg1 ...)
        bpl @set_ppuaddr
        ; fetch first argument for common operations
        inx             ; a=opcode (x)(arg1 ...)
        ldy QDraw,x     ; a=opcode (x)y=(arg1) (...)
        DO cmp #QImmediate, beq @immediate
        DO cmp #QFill, beq @fill
        DO cmp #QTransfer, beq @transfer
        DO cmp #QHorizontal, beq @horizontal
        DO cmp #QVertical, beq @vertical
    ;@break: ; $?? (x)... ; unknown opcode
        ; end frame: defer rest to next nmi
        bne @leave
    @immediate: ; $80 (x)y=len val1 val2 val3 ...
    :   inx
        lda QDraw,x     ; val#
        sta PpuData
        dey
        bne :-
        beq @inx_and_loop
    @fill: ; $81 (x)y=len val
        inx
        lda QDraw,x     ; val
    :   sta PpuData
        dey
        bne :-
        beq @inx_and_loop
    @transfer: ; $82 (x)y=len $hh $ll
        sty NmiW        ; len
        inx
        lda QDraw,x     ; $hh
        sta NmiW+2      ; read addr high
        inx
        lda QDraw,x     ; $ll
        sta NmiW+1      ; read addr low
        ldy #0          ; scan fwd from 0...
    :   lda (NmiW+1),y
        sta PpuData
        iny
        cpy NmiW        ; ...until len
        bne :-
        beq @inx_and_loop
    @horizontal: ; $83
        lda %11111011   ; mode bit off
        and NmiCtrl
        sta NmiCtrl     ; set in shadow
        sta PpuCtrl     ;   and hardware
        jmp @loop
    @vertical: ; $84
        lda %00000100   ; mode bit on
        ora NmiCtrl
        sta NmiCtrl     ; set in shadow
        sta PpuCtrl     ;   and hardware
        jmp @loop
    @set_ppuaddr: ; (x)a=$hh $ll ; $hh.7 was 0
        sta PpuAddr     ; write addr high
        inx
        lda QDraw,x     ; $ll
        sta PpuAddr     ; write addr low
        ; this operation is last so it can fallthru:
    @inx_and_loop:
        inx
    @loop:
        inc NmiBusy     ; tally one command finished
        bpl @interpret  ; less than 127?
        ldx QCommit     ; abandon >127 probably runaway queue
@leave:
    stx QTail       ; mark finished
    ; TODO poll joypad, scan kb?
    DO pla, tay, pla, tax
    lda #0
    sta NmiBusy     ; unlock re-entry
    pla
    rti

; MAIN ------------------------------------------------------

.segment "RODATA"
Palettes:
    .repeat 8
        .byte $0F, $29, $17, $20
    .endrepeat

.segment "CODE"
warm: ; ppu warm, ~1700c vblank left, nmi/render off.
    ; load palettes:
    ldx #$3f
    ldy #0
    stx PpuAddr
    sty PpuAddr
:   lda Palettes,y  ; cpu Palettes
    sta PpuData     ; -> ppu $3f00..1f
    iny
    cpy #$20        ; 32 bytes
    bne :-
    ; x = 0, y = $20. clear background:
    sty PpuAddr
    stx PpuAddr     ; $2000
    ldy #8          ; 8 pages: both screens
:   stx PpuData     ; TODO stx abc, sty blank, sta '?'
    inx
    bne :-
    dey
    bne :-
quit: ; finally init vars and enable nmi:
    ldx #0          ; empty pstack
    stx NmiBusy     ;   unlock nmi just in case
    lda #%00011110  ; sprites, bg, left column spr/bg
    sta NmiMask     ;   enable
    lda #$80        ; nmi
    sta NmiCtrl     ;   stay enabled
    sta PpuCtrl     ;   and enable now
    lda #$f8        ; wrap one tile left, for overscan
    sta NmiScrollX
main: ; ready to go.
    lda NmiFrames
:   cmp NmiFrames  ; wait for one frame
    beq :-
    lda #1 ; pixel
    clc
    adc NmiScrollY ; scroll up
    tay
    cmp #240
    bcc :+          ; not between screens?
    sbc #240        ; a = a-240-(1-c)
    tay
    lda #2
    eor NmiCtrl    ; (two data races here)
    sta NmiCtrl    ; flip screen (ntbl)
:   sty NmiScrollY
    jmp main
