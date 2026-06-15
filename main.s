
; experiments and studies towards a family forth.
; a goal is to port <https://github.com/ekipan/sss> to it.
; lots of TODO design tradeoffs to consider.

; contents: [x] macros [m] memory map [k] keyboard
;   [v] video [t] tty [i] interrupts [f] forth
;
; jump around by grepping crossref markers or names:
;   /\[v0\]/ /code_label:/ /DataLabel:/ /ConstantName =/

.segment "VECTORS" ; https://www.nesdev.org/wiki/CPU_memory_map
.addr nmi, reset, irq ; look for "vectors" on that page.

.segment "INES" ; https://www.nesdev.org/wiki/NES_2.0
.byte "NES", $1a, PROM&$ff, CROM&$ff ; 0-5
.byte ((MAPPER&$f)<<4) | ((PSRAM+CSRAM>0)<<1) | MIRROR ; 6
.byte (MAPPER&$f0) | 8 ; 7: hw nes, binfmt nes2.0
.byte (MAPPER>>8), ((PROM>>4)&$f0)|(CROM>>8)&$f ; 8-9
.byte (PSRAM<<4)|PWRAM, (CSRAM<<4)|CWRAM ; 10-11
.byte 0, 0, 0, PERIPH ; 12-15
; see Makefile for cart config defines.

; [x] I HATE SCROLLING --------------------------------------

; time for a bad first impression! check this out:

.macro COMMA IXN ; insert a comma before final x or y.
    .local R ; rightmost token
    .define R .right(1, {IXN})
    .if .xmatch({R}, x) .or .xmatch({R}, y)
        .left(.tcount({IXN}) - 1, {IXN}), R
    .else ; otherwise just a plain instruction:
        IXN
    .endif ; eg: COMMA lda $20 x   ; -> lda $20,x
.endmacro  ; eg: COMMA sta ($40) y ; -> sta ($40),y

; what a goofy macro. why tf would anyone want this? well:

.macro _ I,J,K,L,M,N,O,P ; list of instructions.
    .if .not .blank({I}) ; up to 8:
        COMMA I
        _ J,K,L,M,N,O,P
    .endif ; eg: _ pha, txa, pha, tya, pha
.endmacro  ; eg: _ lda $20 x, sta ($40) y, jmp foo
; rule: loads at start, 0/1 branches at end.

; MY IRONCLAD BELIEF: code is easier to read when I don't
; have to constantly scroll up and down, losing context. it
; should be *right there*, as much as I can fit on-screen.
; you can disagree, but you're wrong.

; it does break mesen's source view but its disassembly view
; has proved wonderfully capable in my debugging.

; [m] MEMORY MAP --------------------------------------------

.zeropage ; $00-ff system state.

; registers:
;   pc   subroutine-threaded, so forth's ip too.
;   sp   return stack offset in page 1.
;   x    parameter stack offset: $e0-ff or 0 (empty).
;   y/a  scratch, often: y=[H], a=[L].

; the parameter stack:
     .res 32
L:   .res 32 ; \ push-down, x-indexed, split parameter stack
H:           ; / to pass data between words. depth 1: x = $ff.
; - splitting prevents x-misalignment, and:
; - permits push/pop with a single dex/inx instruction.
; - user overflow wraps to free space at end of zeropage.
; - shallow underflow damages scratch first:

; scratch space:
V:   .res 3 ; draw scratch.       \ interrupt
K:   .res 4 ; kb scanner scratch. / routines.
W:   .res 2 ; \ general forth scratch, with
Src: .res 2 ; | pointers for y-indexed
Dst: .res 2 ; / byte transfers.

; global configuration [i]:
Config: .res 1 ; %in?????? custom irq/nmi.
Nmi:    .res 2 ; \ handler routine pointers. set Config
Irq:    .res 2 ; / to 0 first to update atomically.
Frames: .res 1 ; nmi count, for synching or delaying.
Mutex:  .res 1 ; nonzero: nmi locked, plus draw tally.
; a degenerate draw queue eventually tallies Mutex to 128+,
; the draw interpreter abandons, nmi recovers [v0].

; kb driver [k]:  K KbPrev KbHeld KbDown KbBuf
KbHead: .res 1 ; 1) scanner adds. \ $0-ff KbBuf bounds,
KbTail: .res 1 ; 2) main takes.   / modulo KbLen.
KbLen = 4 ; power of 2. head - tail <= len, modulo 256.

; video driver [v]:  V VCmds
OamPg: .res 1 ; or 0 to use DefaultOam.
VCtrl: .res 1 ; \ shadow registers [v2] sent next draw.
VMask: .res 1 ; | VCtrl.7 ignored: nmi is kept enabled.
VSclX: .res 1 ; | careful of data races. for synchronous
VSclY: .res 1 ; / drawing: 0->VMask, vsync, inc Mutex.
; $0-ff VCmds draw queue indices:
VHead:   .res 1 ; 1) main appends commands here.
VCommit: .res 1 ; 2) main moves this fwd to publish to draw.
VTail:   .res 1 ; 3) draw interprets and moves fwd.
; conceptually tail <= commit <= head, though since they
; wrap in memory that'll often not be literally true.

; tty driver [t]:
CsrCol: .res 1 ; 0-31, width of screen.
CsrRow: .res 1 ; 0-253, except seam rows 30,31,62,63 etc
; vaddr calc drops CsrRow.6-7, so effectively 0-29,32-61.
; last two columns are in overscan caution zone.
; TODO reconsider design, might fix CsrRow in 0-59 instead.

; forth interpreter [f]:
; planned: Base, Here, Latest, Pending, InPtr, InEnd.

.bss ; $100-7ff buffers on mainboard ram.

        .res 256 ; hardware stack at $100-1ff.
VCmds:  .res 256 ; draw commands queue. encodings: [v1].
KbPrev: .res 9 ; \ 72 bits arrays of scanned keystates.
KbHeld: .res 9 ; / 0 = unheld, 1 = held.
KbDown: .res 9 ; precomputed down-edges Prev->Held.
KbBuf:  .res KbLen ; scancodes: 0-71, +72 shift held.

.data ; $6000-60ff buffers on cart.

DefaultOam: .res 256 ; sprites data, at $200 conventionally.
; user can configure via OamPg to reuse this space.

; $6100-7fff - ram
;   reserved for scratch to compile user programs into. long
;   term program storage should be in source form, via forth's
;   BLOCK mechanism (once implemented), recompiled on-the-fly.
;
; $8000-bfff - rom (plans TODO)
;   rom dictionary, then blocks of help text, sample code,
;   etc. ideally extra banks, copied into $400 buffer.
;
; $c000-ffff - rom
;   nes hardware drivers and forth kernel.

.code ; [k] KB DRIVER ---------------------------------------

; in-progress. next: higher-level key queue pull.

wait_36c: ;  cycles per line | cumulative
          jsr wait_12c ; 12c | 18c <- 6c jsr wait_36c
          jsr wait_12c ; 12c | 30c
wait_12c: rts          ;  6c | 36c 12c <- 6c jsr wait_12c

; https://www.nesdev.org/wiki/Family_BASIC_Keyboard#Hardware_interface
Joy1 = $4016 ; %?????mcr strobe matrix, select column, reset.
Joy2 = $4017 ; %???kkkk? 0 = keys held on current row/column.
; switching Joy1.1 high to low advances to next row.

kb_quickscan: ; 104c: scan row 0 col 1, stop/rshift keys.
    _ lda #5, sta Joy1, jsr wait_12c  ; reset to row 0.
    _ lda #6, sta Joy1                ; strobe col 1, wait 50c:
    _ jsr wait_36c, nop, nop          ;  40c
    _ lda #$f0, and @Row0, sta @Row0  ;  10c clear previous.
    _ lda Joy2, lsr, and #$f, eor #$f ; read, parse: %0000kkkk
    _ ora @Row0, sta @Row0, rts       ; update array.
    @Row0 = KbHeld+8

kb_fullscan: ; scan the entire keyboard.
    ; 9 rows * 2 cols * 4 bits = 72 keys.
    ; 1235c full buffer, 1383c idle, 1606c buffer +1.
    _ lda #5, sta Joy1 ; reset keyboard to row 0.
    jsr wait_12c
    _ lda #4, sta Joy1 ; strobe column 0. wait 50c:
    ; interleave work while waiting for the matrix to settle:
    ; cycle counts:     line accum
    _ jsr wait_36c, bit 0 ;  39c
    ldy #8             ;  2c 41c  scan 9 rows: 8-0.
:   lda KbHeld,y       ;  4c 45c  \ save previous scan
    sta KbPrev,y       ;  5c 50c  / while we're here.
    _ lda Joy2, sta K  ; read column 0: %???kkkk? 0 = held
    _ lda #6, sta Joy1 ; strobe column 1. wait 50c:
    jsr wait_36c       ; 36c 36c
    _ lda K, asl, asl  ;  7c 43c  %?kkkk?00 <- column 0
    _ asl, and #$f0    ;  4c 47c  %kkkk0000
    sta K              ;  3c 50c
    _ lda Joy2, sta K+1 ; read column 1: %???kkkk? 0 = held
    _ lda #4, sta Joy1 ; strobe next row column 0, wait 50c:
    _ lda K+1, lsr     ;  5c  5c  %0???kkkk <- column 1
    _ and #$0f, ora K  ;  5c 10c  %kkkkkkkk
    eor #$ff           ;  2c 12c  1 = curr held
    sta KbHeld,y       ;  5c 17c
    lda KbPrev,y       ;  4c 21c  1 = prev held
    eor #$ff           ;  2c 23c  1 = prev unheld
    and KbHeld,y       ;  4c 27c  1 = prev unheld & curr held
    sta KbDown,y       ;  5c 32c  i.e. pressed
    _ nop, nop         ;  4c 36c
    _ dey, bpl :-      ;  5c 41c -> : 4c+5c 50c  more rows?
    ;
    ; now for the hard part, interpreting KbDown key event
    ; bits into scancodes to push onto the KbBuf queue.
    ;
    _ @Shift = K+0, @SC = K+1, @TmpX = K+2, @TmpY = K+3
    ;
    _ jsr @is_queue_full, beq @rts
    _ lda #0, sta @Shift  ; 0 default scancode.
    _ lda KbHeld+8, and #2, bne :+  ; rshift row 0 key 1
    _ lda KbHeld+1, and #1, beq :++ ; lshift row 7 key 0
:   _ lda #72, sta @Shift ; 72 shifted scancode offset.
:   ; what a big tangly mess!
    _ stx @TmpX ; save pstack.
    _ ldx #0 ; x = 0->8 row byte index.
  @scan_all:
    _ lda KbDown x, bne @scan_row ; presses on row x?
  @next_row:
    _ inx, cpx #9, bne @scan_all, beq @done
  @scan_row:
    _ ldy #0 ; y = 0->7 key bit index. inner loop:
  @scan_bit:
    _ lda KbDown x, and Bitmasks y, bne @buffer_key
    _ iny, cpy #8, bne @scan_bit, beq @next_row
  @buffer_key: ; compute and store scancode:
    _ txa, asl, asl, asl, sta @SC, clc  ; %0rrrr000
    _ tya, ora @SC, adc @Shift, sta @SC ; %0rrrrccc + 0/72
    _ lda KbHead, and #KbLen-1 ; masked ringbuf index
    _ sty @TmpY ; stash bit index, append to queue:
    _ tay, lda @SC, sta KbBuf y, inc KbHead
    _ ldy @TmpY ; restore bit index.
    _ jsr @is_queue_full, beq @done
    _ iny, cpy #8, bne @scan_bit, beq @next_row
  @done:
    _ ldx @TmpX ; restore pstack.
  @rts:
    _ rts
@is_queue_full: ; subroutine. flag: head - tail == len?
    _ lda KbHead, sec, sbc KbTail, cmp #KbLen, rts

Bitmasks:
    .byte 1, 2, 4, 8, $10, $20, $40, $80

stop_ne_rshift_cs: ; 22c: flag most recent stop/rshift keys.
    _ lda KbHeld+8 ; row 0 %kkkkskrk
    _ lsr, lsr, and #2, rts ; use bne/bcs to react.

.code ; [v] VIDEO DRIVER ------------------------------------

; https://www.nesdev.org/wiki/PPU
; the picture processing unit rejects i/o while drawing the
; screen, draw commands must be sent during 2270c vblank, so
; I encode them into a ring buffer to send asynchronously.
;
; https://github.com/bbbradsmith/NES-ca65-example/blob/1bb961dcdf317f39460c0c28a13f33a82feb29c4/example.s#L200-L232
; design grown out from this, do refer to it!

; [v2] https://www.nesdev.org/wiki/PPU_registers
PpuCtrl =   $2000 ; %n?tbsvyx nmi tall bgpat sprpat vert yxtbl
PpuMask =   $2001 ; %rgbsbllg dimrgb spr bg leftcol greysc
PpuStatus = $2002 ; %vzo????? vblank zerohit overflow
OamAddr =   $2003 ; ppu write offset, nonzero corrupts oam!
PpuScroll = $2005 ; send x then y \ touch PpuStatus
PpuAddr =   $2006 ; addrh, addrl  / to reset order latch
PpuData =   $2007 ; increments by 1 or 32 (PpuCtrl vert)
OamDma =    $4014 ; (cpu) page to transfer to ppu

draw: ; ~2240c left after nmi prologue.
    _ lda #1, sta Mutex ; lock nmi for synch'd draw in main.
    bit PpuStatus ; reset PpuAddr/PpuScroll write latch.
    ; load sprites:
    _ lda VMask, sta PpuMask ; bg/sprites on/off
    _ and #$10, beq :++ ; sprites disabled? -> skip dma
    _ lda OamPg, bne :+ ; custom oam page?
    _ lda #>DefaultOam
:   _ ldy #0, sty OamAddr, sta OamDma ; 519c
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
@put: ; (x)y=len val1 val2 val3 ...
    ; assume 1b sends are the common case and don't unroll.
:   inx
    _ lda VCmds x, sta PpuData, dey, bne :-
    beq @inx_and_loop
@fill: ; (x)y=len val
    inx
    ; unroll to lower overhead. 32b: 291c->249c, 1b: 12c->19c
    _ tya, lsr      ; c = odd len?
    lda VCmds,x     ; val
    bcs :++
:   _ sta PpuData, dey
:   _ sta PpuData, dey
    bne :--
    beq @inx_and_loop ; <- unrolls measured from tya to here.
@set_addr: ; a=$hh (x)y=$ll
    ; rely on caller to reset latch, save 4c:
    ;bit PpuStatus ; draw bugs? uncomment first (!!)
    _ sta PpuAddr, sty PpuAddr
  @inx_and_loop:
    inx
  @loop: ; [v0] prevent lock-up from a malformed queue:
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
    _ cmp #VPut, beq @put     ; workhorse draw
    _ cmp #VFill, beq @fill   ; clearing/blocking out
    _ cmp #VPace, beq @pace   ; separate batches
    _ cmp #VSend, beq @send   ; usually during setup
    _ cmp #VVert, beq @vert   ; switch to columns
    _ cmp #VHoriz, beq @horiz ; back to default
    ; malformed command.
  @abandon:
    ldx VCommit
  @rts:
    rts
@send: ; (x)y=len $hh $ll
    _ @Ptr = V+0, @Len = V+2 ; local scratch names:
    _ sty @Len, inx
    _ lda VCmds x, sta @Ptr+1, inx
    _ lda VCmds x, sta @Ptr
    ; unrolled. 32b: 566c->486c, 1b: 18c->25c
    _ tya, lsr  ; c = odd len?
    ldy #0      ; scan fwd from 0 to len:
    bcs :++
:   _ lda (@Ptr) y, sta PpuData, iny
:   _ lda (@Ptr) y, sta PpuData, iny
    _ cpy @Len, bne :--
    beq @inx_and_loop ; <- unrolls measured tya to here.
@pace: ; end frame and defer to next nmi if we've drawn
    ; Mutex: draw stores 1, @horiz inc's, so 2 = no draws:
    _ lda Mutex, cmp #$02, beq @decode ; no draws yet?
    rts

; [v1] VCmds encodings:
; $0-3f: set PpuAddr. other opcodes far away so overflowed
;        addresses are less likely to be misinterpreted:
VHoriz = $a0 ; \ reset/set increment mode
VVert =  $a1 ; / bit PpuCtrl.1 (+1/32)
VPut =   $a2 ; args: len val1 val2 val3 ...
VFill =  $a3 ; args: len val
VSend =  $a4 ; args: len addrh addrl
VPace =  $a5 ; stop drawing until next frame
; unknown opcodes drop the queue, moving VTail to VCommit.

; TODO more high-level words to push commands.

.code ; [t] TTY DRIVER --------------------------------------

vsync: ; ( -- ) wait for next vblank.
    _ lda #0, sta Mutex ; TODO stash and restore?
    lda Frames
:   _ cmp Frames, beq :-
    rts

vcommit: ; ( -- ) send queued draw commands.
    _ lda VHead, sta VCommit, rts

vcmd: ; append a byte to the queue.
    ldy VHead
    ; TODO vsync to progress if VHead at VTail? probably
    ; lots of degenerate edge cases. needs research.
    sta VCmds,y
    _ inc VHead, rts

; nw ntb0 -> [ $2000-23ff ][ $2400-27ff ] <- ne ntb1  \ 1k
; sw ntb2 -> [ $2800-2bff ][ $2c00-2fff ] <- se ntb3  / each
;
; most carts map nametables 0-3 to the ppu internal 2k,
; mirroring either horizontally or vertically. ntb1 and 2 are
; contiguous in memory and pair with both configurations.

vaddr_csr: ; put cursor vaddr onto draw queue.
    _ ldy CsrRow, lda CsrCol
vaddr_ya:
    _ and #$1f, sta W+1 ; compute: $2400 + ((y&63)<<5|(a&31))
    _ lda #$00, sta W           ; W %00000000  y %??rrrrrr
    _ tya, asl, asl, asl, rol W ; W %0000000r  a %rrrrr000
    _ asl, rol W, asl, rol W    ; W %00000rrr  a %rrr00000
    _ ora W+1, sta W+1
    _ lda W, clc, adc #$24, jsr vcmd ; vaddrh
    _ lda W+1, jmp vcmd ; vaddrl

rawemit: ; ( c -- ) display a character.
    _ jsr vaddr_csr, inc CsrCol
    _ lda CsrCol, cmp #32, bcc :+ ; still on screen?
    jsr cr ; no: go to next line
:   _ lda #VPut, jsr vcmd, lda #1, jsr vcmd ; put one
    _ lda L x, inx, jsr vcmd, jmp vcommit   ; character

cr: ; ( -- ) move the cursor to the start of next line.
    _ lda #VPace, jsr vcmd ; 64b is risky, pace before/after.
    _ lda #$00, sta CsrCol  ; col = 0, increment row:
    _ ldy CsrRow, jsr @iny, sty CsrRow, jsr @clear ; and clear.
    _ ldy CsrRow, jsr @iny, jsr @clear ; and below screen.
    ; TODO scroll.
    _ lda #VPace, jsr vcmd, jmp vcommit
@iny:
    _ iny, tya, and #31, cmp #30, bcc :+ ; still in-screen?
    _ iny, iny ; pass over attrtable seam.
:   rts
@clear:
    _ lda #0, jsr vaddr_ya ; at row address:
    _ lda #VFill, jsr vcmd ; fill
    _ lda #32, jsr vcmd    ; an entire row
    _ lda #' ', jmp vcmd   ; with spaces

palette_move:
    _ lda #$3f, jsr vcmd, lda #0, jsr vcmd    ; to $3f00
    _ lda #VSend, jsr vcmd, lda #32, jmp vcmd ; send 32b

page: ; ( -- ) init and clear the screen.
    ; called on reset, must enable nmi directly! but *also*
    ; must be callable during normal interpreter use. ~0.6f.
    _ lda #1, sta Mutex ; lock nmi if it's running.
    _ lda #0, sta Config, sta VMask, sta CsrRow, sta CsrCol
    _ sta VCommit, sta VTail, sta VHead ; delete the queue
    _ jsr palette_move ; and set the default palette:
    _ lda #>RomPalette, jsr vcmd
    _ lda #<RomPalette, jsr vcmd, jsr vcommit
    ; scroll cursor in from the bottom of ntb2:
    _ lda #$f8, sta VSclX ; 1 col left  \ overscan
    _ lda #$18, sta VSclY ; 3 rows down / blue area.
    ; https://www.nesdev.org/wiki/Overscan
    _ lda #$82, sta VCtrl, sta PpuCtrl ; enable nmi, ntb2.
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

.rodata

RomPalette:
    .repeat 8
        .byte $0F, $29, $17, $20
    .endrepeat

.code ; [i] INTERRUPTS --------------------------------------

DmcFreq = $4010 ; TODO document.

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
:   _ lda #$ff, sta $6000 x, lda #0 ; DefaultOam
    _ sta $000 x, sta $100 x, sta $200 x, sta $300 x
    _ sta $400 x, sta $500 x, sta $600 x, sta $700 x
    _ inx, bne :-
:   _ bit PpuStatus, bpl :- ; second frame
    _ jsr page, jmp main ; clear bg, start nmi, start main

nmi: ; vblank: 2270c deadline to finish drawing
    _ bit Config, bvc :+ ; default nmi service?
    jmp (Nmi) ; no, custom
:   _ pha, tya, pha ; subroutines responsible for x.
    _ lda Mutex, bne :+ ; re-entered?
    inc Frames ; notify main a vblank happened.
    jsr draw   ; store 1 in Mutex and process queue.
    ; TODO poll Joy1? sound?
    jsr kb_fullscan ; >1200c, 10.6 scanlines
    ; jsr kb_quickscan ; TODO configurable scan type.
    jsr stop_ne_rshift_cs ; flag scanned recovery keys.
    bne reset ; pressed stop? TODO recover instead.
    _ lda #0, sta Mutex ; unlock next frame
:   _ pla, tay, pla, rti

irq: ; unused, but configurable.
    _ bit Config, bpl :+
    jmp (Irq)
:   rti

.code ; [f] FORTH -------------------------------------------

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

main:
    _ lda #1, jsr add_y, jsr vsync, jmp main
