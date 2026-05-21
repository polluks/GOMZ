; MZMON - Sharp MZ-80K Monitor Port for Commodore 128 Z80 Mode
;
; vasm oldstyle: vasmz80_oldstyle -Fbin -o mzmon.bin mzmon.asm
;
; Runs on C128 Z80. Uses I/O ports for hardware access:
;   OUT (C),A / IN A,(C) for VDC ($D600-$D601) and CIA ($DC00-$DC01)
;
; Boot: 6502 loader copies this to RAM, sets Z80 vector, switches CPU.
; MMU config: all RAM Bank 0 ($0000-$FFFF = 64KB RAM).

    org $C000

; I/O port addresses
VDCA      equ $D600    ; VDC address/status port (I/O)
VDCD      equ $D601    ; VDC data port (I/O)
CIA1A     equ $DC00    ; CIA1 Port A (keyboard rows, I/O)
CIA1B     equ $DC01    ; CIA1 Port B (keyboard columns, I/O)

; VDC internal register numbers (OUT VDCA,regnum; then OUT VDCD,value)
VR_HTOTAL    equ 0
VR_HDISP     equ 1
VR_HSYNC     equ 2
VR_HSYNCW    equ 3
VR_VTOTAL    equ 4
VR_VADJ      equ 5
VR_VDISP     equ 6
VR_VSYNC     equ 7
VR_ILACE     equ 8
VR_CHRH      equ 9
VR_CURCTL    equ 10
VR_CURSTART  equ 11
VR_SAHIGH    equ 12
VR_SALOW     equ 13
VR_CURHIGH   equ 14
VR_CURLOW    equ 15
VR_UPDHIGH   equ 18
VR_UPDLOW    equ 19
VR_CGBASE    equ 20
VR_FGCOLOR   equ 23
VR_ROWINCR   equ 24
VR_CHRGAP    equ 25
VR_MEMREFR   equ 31   ; data register for VRAM access

; Screen
COLS equ 40
ROWS equ 25
SZ   equ COLS*ROWS

; ===== ENTRY =====
start:
    di
    ld sp,$4000

    ; Init VDC for 40x25 display
    call vdc_init

    ; Set up SP-1002 compatibility stubs at $0000
    call compat_setup

    ; Clear screen
    call vdc_clear

    ; Show banner
    ld hl,welcome
    call vdc_puts

    ; Copy SID driver to $7F00 for MMU-safe I/O access
    ld hl,sid_driver_start
    ld de,$7F00
    ld bc,sid_driver_end - sid_driver_start
    ldir

    ; Show prompt
prompt:
    ld hl,prompt_msg
    call vdc_puts

    ; Read and process commands
main:
    call read_line
    call exec_cmd
    jr prompt

; ===== VDC DRIVER (via Z80 I/O ports) =====

; Write A to VDC internal register A
vdc_wreg:
    push bc
    ld c,VDCA & 255
    out (c),a        ; select register
    pop bc
    ret

; Write A to VDC data (after selecting register)
vdc_wdat:
    push bc
    ld c,VDCD & 255
    out (c),a
    pop bc
    ret

; Set VDC display VRAM update address to HL
vdc_set_addr:
    push af
    ld a,VR_UPDHIGH
    call vdc_wreg
    ld a,h
    call vdc_wdat
    ld a,VR_UPDLOW
    call vdc_wreg
    ld a,l
    call vdc_wdat
    pop af
    ret

; Write A to VDC VRAM at current update address (auto-increment)
vdc_vram:
    push bc
    ld c,VDCD & 255
    out (c),a
    pop bc
    ret

; Initialize VDC for 40x25, 8x8 chars
vdc_init:
    ; Registers from TRSDOS style with 40-col values
    ld a,VR_HTOTAL
    call vdc_wreg
    ld a,63          ; 40 + 23 (hblank)
    call vdc_wdat

    ld a,VR_HDISP
    call vdc_wreg
    ld a,COLS        ; 40
    call vdc_wdat

    ld a,VR_HSYNC
    call vdc_wreg
    ld a,52          ; hsync position
    call vdc_wdat

    ld a,VR_HSYNCW
    call vdc_wreg
    ld a,14          ; hsync width
    call vdc_wdat

    ld a,VR_VTOTAL
    call vdc_wreg
    ld a,33          ; 25 + 8 (vblank)
    call vdc_wdat

    ld a,VR_VADJ
    call vdc_wreg
    ld a,1
    call vdc_wdat

    ld a,VR_VDISP
    call vdc_wreg
    ld a,ROWS        ; 25
    call vdc_wdat

    ld a,VR_VSYNC
    call vdc_wreg
    ld a,28
    call vdc_wdat

    ld a,VR_ILACE
    call vdc_wreg
    xor a             ; no interlace
    call vdc_wdat

    ld a,VR_CHRH
    call vdc_wreg
    ld a,8            ; 8 scan lines per char
    call vdc_wdat

    ld a,VR_CURCTL
    call vdc_wreg
    xor a             ; cursor off
    call vdc_wdat

    ld a,VR_CURSTART
    call vdc_wreg
    xor a
    call vdc_wdat

    ; Display start at VRAM $0000
    ld a,VR_SAHIGH
    call vdc_wreg
    xor a
    call vdc_wdat

    ld a,VR_SALOW
    call vdc_wreg
    xor a
    call vdc_wdat

    ; CG RAM base at $2000
    ld a,VR_CGBASE
    call vdc_wreg
    ld a,$01           ; $2000 >> 13
    call vdc_wdat

    ; Color: white on black
    ld a,VR_FGCOLOR
    call vdc_wreg
    ld a,$07
    call vdc_wdat

    ; Row increment
    ld a,VR_ROWINCR
    call vdc_wreg
    ld a,COLS
    call vdc_wdat

    ; Char gen spacing
    ld a,VR_CHRGAP
    call vdc_wreg
    ld a,8
    call vdc_wdat

    ret

; Clear VDC screen (fill with spaces)
vdc_clear:
    push af
    push hl
    ld hl,0
    call vdc_set_addr
    ld hl,SZ
clr_l:
    ld a,' '
    call vdc_vram
    dec hl
    ld a,h
    or l
    jr nz,clr_l
    pop hl
    pop af
    ret

; Output char A to VDC at cursor
vdc_putc:
    push af
    push hl
    cp $0A
    jr z,vdc_nl
    cp $08
    jr z,vdc_bs

    ; Read cursor from VDC
    ld a,VR_CURHIGH
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld h,a
    pop bc
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc

    ; Set VRAM addr to cursor
    call vdc_set_addr
    pop af
    push af
    call vdc_vram

    ; Increment cursor
    inc hl
    push hl
    ld de,-COLS
    add hl,de
    pop hl
    jr c,vdc_setc     ; no wrap if within row
    ; Wrap: (hl / COLS) * COLS + ... no, just find start of next row
    ld a,VR_CURHIGH
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld h,a
    pop bc
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc
    ld de,COLS
    add hl,de
    jr vdc_setc

vdc_nl:
    ; Move cursor down one row
    ld a,VR_CURHIGH
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld h,a
    pop bc
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc
    ld a,l
    and $FF-COLS      ; find row start within 64KB... simpler: just add COLS
    ld l,a            ; keep column as-is by adding COLS
    ; Actually no. For newline, go to start of next row
    ; Current row = floor(hl / COLS), next row start = (row+1)*COLS
    push hl
    ld a,COLS
    call div_a_hl     ; divide HL by A
    inc hl            ; next row
    ld a,COLS
    call mul_a_hl     ; multiply HL by A
    jr vdc_setc

vdc_bs:
    ; Backspace: decrement cursor
    ld a,VR_CURHIGH
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld h,a
    pop bc
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc
    dec hl

vdc_setc:
    ; Write cursor position HL back to VDC
    ld a,VR_CURHIGH
    call vdc_wreg
    ld a,h
    call vdc_wdat
    ld a,VR_CURLOW
    call vdc_wreg
    ld a,l
    call vdc_wdat
    pop hl
    pop af
    ret

; Output null-terminated string at HL
vdc_puts:
    ld a,(hl)
    or a
    ret z
    cp $0A
    jr nz,vdp_ch
    push hl
    call vdc_nl_cursor
    pop hl
    inc hl
    jr vdc_puts
vdp_ch:
    call vdc_putc
    inc hl
    jr vdc_puts

vdc_nl_cursor:
    ; Just move cursor to next row start
    push af
    push hl
    ld a,VR_CURHIGH
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld h,a
    pop bc
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc
    push hl
    ld a,COLS
    call div_a_hl
    inc hl
    ld a,COLS
    call mul_a_hl
    ld a,VR_CURHIGH
    call vdc_wreg
    ld a,h
    call vdc_wdat
    ld a,VR_CURLOW
    call vdc_wreg
    ld a,l
    call vdc_wdat
    pop hl
    pop hl
    pop af
    ret

; Output A as 2 hex digits
vdc_hex8:
    push af
    push af
    rrca
    rrca
    rrca
    rrca
    call vdc_nib
    pop af
    call vdc_nib
    pop af
    ret
vdc_nib:
    and $0F
    add a,$90
    daa
    adc a,$40
    daa
    jp vdc_putc

; Output HL as 4 hex digits
vdc_hex16:
    ld a,h
    call vdc_hex8
    ld a,l
    call vdc_hex8
    ret

; Divide HL by A, result in HL
div_a_hl:
    push bc
    ld c,a
    ld b,16
    xor a
div_l:
    add hl,hl
    rla
    cp c
    jr c,div_s
    sub c
    inc l
div_s:
    djnz div_l
    pop bc
    ret

; Multiply HL by A, result in HL
mul_a_hl:
    push bc
    ld b,a
    ld a,h
    ld c,l
    ld hl,0
mul_l:
    add hl,bc
    djnz mul_l
    pop bc
    ret

; ===== KEYBOARD (CIA1 via I/O ports) =====

; Read a line of input into ibuf
read_line:
    push af
    push hl
    push bc
    ld hl,ibuf
    ld b,0
rll:
    call getkey
    or a
    jr z,rll
    cp $0D
    jr z,rldone
    cp $08
    jr nz,rle
    ld a,b
    or a
    jr z,rll
    dec hl
    dec b
    ld a,$08
    call vdc_putc
    jr rll
rle:
    cp ' '
    jr c,rll
    ld (hl),a
    inc hl
    inc b
    call vdc_putc
    ld a,b
    cp 63
    jr c,rll
rldone:
    ld (hl),0
    ld a,$0D
    call vdc_putc
    ld a,$0A
    call vdc_putc
    pop bc
    pop hl
    pop af
    ret

; Get keypress, returns ASCII or 0
getkey:
    push bc
    push hl
    push de

    ; Scan keyboard matrix via CIA1
    ; Rows driven by Port A (output), columns read via Port B (input)
    ; Scan 8 rows

    ld hl,kmap
    ld b,8
    ld c,$FE          ; start row select (CIA1A)

gk_rl:
    push bc
    ; Output row select to CIA1A
    ld a,c
    push bc
    ld c,CIA1A & 255
    out (c),a
    pop bc
    ; Small delay
    nop
    nop
    ; Read columns from CIA1B
    push bc
    ld c,CIA1B & 255
    in a,(c)
    pop bc
    cpl               ; 1 = pressed
    
    ld d,a
    ld e,1
    ld b,8
gk_cl:
    ld a,d
    and e
    jr nz,gk_hit
    sla e
    inc hl            ; next key in map
    djnz gk_cl
    
    pop bc
    ; Next row
    ld a,c
    scf
    rla
    ld c,a
    djnz gk_rl
    
    xor a             ; no key
    jr gk_done

gk_hit:
    ld a,(hl)         ; ASCII from map
    or a
    jr z,gk_rel       ; undefined key
    ld e,a

    ; Wait for key release
gk_wr:
    push bc
    ld c,CIA1A & 255
    out (c),a
    pop bc
    nop
    nop
    push bc
    ld c,CIA1B & 255
    in a,(c)
    pop bc
    cpl
    and d
    jr nz,gk_wr

    ld a,e
gk_done:
    pop de
    pop hl
    pop bc
    ret

gk_rel:
    ; Undefined key - wait for release, return 0
    push bc
    ld c,CIA1A & 255
    out (c),a
    pop bc
    nop
    nop
    push bc
    ld c,CIA1B & 255
    in a,(c)
    pop bc
    cpl
    and d
    jr nz,gk_rel
    xor a
    jr gk_done

; C128 keyboard matrix -> ASCII (US, uppercase)
; 8 rows x 8 columns
kmap:
    ; Row 0 ($FE)
    db '1','3','5','7','9','-',$08,0
    ; Row 1 ($FD)
    db 'Q','E','T','U','O','@',$0D,$1B
    ; Row 2 ($FB)
    db 'A','D','G','J','L',':',0,0
    ; Row 3 ($F7)
    db 'Z','C','B','M','.',' ','/',0
    ; Row 4 ($EF)
    db '2','4','6','8','0','_',';',0
    ; Row 5 ($DF)
    db 'W','R','Y','I','P','^','+',0
    ; Row 6 ($BF)
    db 'S','F','H','K','<','*','=',0
    ; Row 7 ($7F)
    db 'X','V','N',',','>','?',0,0

; ===== COMMANDS =====

exec_cmd:
    ld a,(ibuf)
    or a
    ret z
    cp 'a'
    jr c,ec_uc
    cp 'z'+1
    jr nc,ec_uc
    sub $20
ec_uc:
    cp 'D'
    jp z,cmd_d
    cp 'M'
    jp z,cmd_m
    cp 'G'
    jp z,cmd_g
    cp 'J'
    jp z,cmd_g
    cp 'L'
    jp z,cmd_l
    cp 'S'
    jp z,cmd_s
    cp 'B'
    jp z,cmd_b
    cp 'H'
    jp z,cmd_h
    ld hl,msg_q
    call vdc_puts
    ret

; Parse hex number after command char
; Returns HL = value, C set on error
parse_hex:
    ld hl,ibuf+1
ph_sk:
    ld a,(hl)
    cp ' '
    jr z,ph_skc
    cp $09
    jr z,ph_skc
    cp 0
    jr z,ph_er
    jr ph_go
ph_skc:
    inc hl
    jr ph_sk
ph_go:
    ld de,0
ph_l:
    ld a,(hl)
    cp ' '
    jr z,ph_dn
    cp $09
    jr z,ph_dn
    cp 0
    jr z,ph_dn
    call hx_val
    jr c,ph_er
    ; DE = DE*16 + A
    push hl
    ld h,d
    ld l,e
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,h
    ld e,l
    pop hl
    or e
    ld e,a
    jr nc,$+3
    inc d
    inc hl
    jr ph_l
ph_dn:
    ex de,hl
    or a
    ret
ph_er:
    scf
    ret

hx_val:
    cp '0'
    jr c,hv_b
    cp '9'+1
    jr c,hv_d
    cp 'A'
    jr c,hv_b
    cp 'F'+1
    jr c,hv_l
    cp 'a'
    jr c,hv_b
    cp 'f'+1
    jr c,hv_l2
hv_b:
    scf
    ret
hv_d:
    sub '0'
    ret
hv_l:
    sub 'A'-10
    ret
hv_l2:
    sub 'a'-10
    ret

; D <addr> - Hex dump
cmd_d:
    call parse_hex
    jp c,badarg
    ld (d_adr),hl
    ld b,8
cd_l:
    push bc
    ld hl,(d_adr)
    call vdc_hex16
    ld a,' '
    call vdc_putc
    ld b,8
cd_h:
    push bc
    ld hl,(d_adr)
    ld a,(hl)
    call vdc_hex8
    ld a,' '
    call vdc_putc
    ld hl,(d_adr)
    inc hl
    ld (d_adr),hl
    pop bc
    djnz cd_h
    ld a,' '
    call vdc_putc
    ld hl,(d_adr)
    ld de,8
    sbc hl,de
    ld b,8
cd_a:
    ld a,(hl)
    cp $20
    jr c,cd_dt
    cp $7F
    jr c,cd_pr
cd_dt:
    ld a,'.'
cd_pr:
    call vdc_putc
    inc hl
    djnz cd_a
    ld a,$0D
    call vdc_putc
    ld a,$0A
    call vdc_putc
    pop bc
    djnz cd_l
    ret

; M <addr> - Modify memory
cmd_m:
    call parse_hex
    jp c,badarg
    push hl
    ld a,(hl)
    call vdc_hex8
    ld hl,msg_m
    call vdc_puts
    ; For now, just show value
    pop hl
    ret

; G <addr> - Go (execute)
cmd_g:
    call parse_hex
    jp c,badarg
    jp (hl)

; L - Load tape
cmd_l:
    ld hl,msg_loading
    call vdc_puts
    ret

; S <start> <end> <exec> - Save tape
cmd_s:
    call parse_hex
    jp c,badarg
    ld (s_st),hl
    ret

; H - Help
cmd_h:
    ld hl,help_txt
    call vdc_puts
    ret

; B - Run SP-5025 BASIC
cmd_b:
    ; Copy SP-5025 from $8000 to $1200 if not already there
    ld hl,$8000
    ld de,$1200
    ld bc,$3000      ; 12KB
    ldir

    ; Initialize SP-1002 work area
    call init_workarea

    ; Jump to BASIC
    jp $1200

; Initialize SP-1002 work area ($1000-$11F5)
init_workarea:
    ; Zero out work area
    ld hl,$1000
    ld de,$1001
    ld bc,$01F5
    ld (hl),0
    ldir

    ; Set cursor position to (0,0)
    ld a,1
    ld ($1191),a     ; cursor on

    ; Init stack pointer for SP-1002 style
    ld sp,$10F0

    ret

badarg:
    ld hl,msg_bad
    call vdc_puts
    ret

; ===== SP-1002 COMPATIBILITY LAYER =====
; Copies stub jump table to $0000 and higher vectors.
compat_setup:
    push af
    push hl
    push de
    push bc
    ; Copy main vector table ($0000-$00xx)
    ld hl,compat_main
    ld de,$0000
    ld bc,compat_main_end-compat_main
    ldir
    ; Copy extra vectors to higher addresses
    ; $03BA: PRTWRD (print HL as 4 hex digits)
    ld hl,compat_extra1
    ld de,$03BA
    ld bc,compat_extra1_end-compat_extra1
    ldir
    ; $0A44: BRKTST (break test)
    ld hl,compat_extra2
    ld de,$0A44
    ld bc,compat_extra2_end-compat_extra2
    ldir
    ; $0DA6: SNCV (wait blanking - just RET)
    ld hl,compat_extra3
    ld de,$0DA6
    ld bc,compat_extra3_end-compat_extra3
    ldir
    ; $0DDC: MOVECU (cursor control)
    ld hl,compat_extra4
    ld de,$0DDC
    ld bc,compat_extra4_end-compat_extra4
    ldir
    pop bc
    pop de
    pop hl
    pop af
    ret

; ===== Main vector table (copied to $0000+) =====
; Each entry is a JP instruction (3 bytes).
; Gaps filled with zeros (NOP padding).
compat_main:
    ; $00: MONIT (cold start)
    jp compat_monit
    ; $03: GETL (line input)
    jp compat_getl
    ; $06: LETNL (CRLF)
    jp compat_crlf
    ; $09: NEWLIN (CRLF if not at line start)
    jp compat_newlin
    ; $0C: PRINTS (space)
    jp compat_space
    ; $0F: TABUL (tab)
    jp compat_tabul
    ; $12: PRNT (char out)
    jp compat_prnt
    ; $15: MSG (string out)
    jp compat_msg
    ; $18: LISTL (literal string)
    jp compat_listl
    ; $1B: GETKY (key in)
    jp compat_getky
    ; $1E: BRKEY (break check)
    jp compat_brkey
    ; $21-$2D: Tape routines (all stubbed)
    jp compat_notape
    jp compat_notape
    jp compat_notape
    jp compat_notape
    jp compat_notape
    ; $30: SNDOUT (MUSIC note start)
    jp compat_sndout
    ; $33-$40: padding
    ds 14, 0
    ; $41: SNDSTOP (MUSIC note end)
    jp compat_sndstop
    ; $44-$81: padding
    ds 62, 0
    ; $82: ST1 (warm start)
    jp compat_monit
compat_main_end:

; Extra: PRTWRD, PRTBYT, DIGASC, ASCDIG at $03BA-$03C5
compat_extra1:
    jp vdc_hex16
    jp vdc_hex8
    jp digasc
    jp ascdig
compat_extra1_end:

; Extra: BRKTST at $0A44
compat_extra2:
    jp compat_brkey
compat_extra2_end:

; Extra: SNCV at $0DA6
compat_extra3:
    ret
    nop
compat_extra3_end:

; Extra: MOVECU at $0DDC
compat_extra4:
    jp movecu
compat_extra4_end:

; ===== Compatibility implementations =====
; These are actual JP instructions that jump to our monitor routines.
; They are at $0000+ after being copied.

compat_monit:
    jp start

compat_st1:
    jp prompt

compat_crlf:
    push af
    ld a,$0D
    call vdc_putc
    ld a,$0A
    call vdc_putc
    pop af
    ret

compat_newlin:
    push af
    push hl
    ; Read cursor position from VDC
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc
    ld a,l
    and $3F           ; column = cursor % COLS (actually just low bits)
    and $FF-COLS+1
    jr z,cnl_done    ; already at start of line
    ld a,$0D
    call vdc_putc
    ld a,$0A
    call vdc_putc
cnl_done:
    pop hl
    pop af
    ret

compat_space:
    push af
    ld a,' '
    call vdc_putc
    pop af
    ret

compat_tabul:
    push af
    push bc
    ; Read cursor column
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld b,a
    pop bc
    ld a,b
    and $3F
    ld b,a
ct_l:
    ld a,' '
    call vdc_putc
    ld a,VR_CURLOW
    call vdc_wreg
    push bc
    ld c,VDCD & 255
    in a,(c)
    ld b,a
    pop bc
    ld a,b
    and $3F
    cp 10
    jr c,ct_l
    pop bc
    pop af
    ret

; PRNT - Character output
; Input: A = ASCII character
; Handles $0D(CR), $11(down), $12(up), $13(right), $14(left), $15(home), $16(clear), $7F(scroll)
compat_prnt:
    cp $0D
    jr z,prnt_cr
    cp $11
    jr z,prnt_down
    cp $12
    jr z,prnt_up
    cp $13
    jr z,prnt_right
    cp $14
    jr z,prnt_left
    cp $15
    jr z,prnt_home
    cp $16
    jr z,prnt_clear
    cp $7F
    jr z,prnt_scroll
    ; Regular character
    jp vdc_putc

prnt_cr:
    push af
    ld a,$0D
    call vdc_putc
    pop af
    ret

prnt_down:
    push af
    push hl
    call get_cursor
    ld de,COLS
    add hl,de
    call set_cursor
    pop hl
    pop af
    ret

prnt_up:
    push af
    push hl
    call get_cursor
    ld de,-COLS
    add hl,de
    call set_cursor
    pop hl
    pop af
    ret

prnt_right:
    push af
    push hl
    call get_cursor
    inc hl
    call set_cursor
    pop hl
    pop af
    ret

prnt_left:
    push af
    push hl
    call get_cursor
    dec hl
    call set_cursor
    pop hl
    pop af
    ret

prnt_home:
    push af
    ld hl,0
    call set_cursor
    pop af
    ret

prnt_clear:
    push af
    call vdc_clear
    ld hl,0
    call set_cursor
    pop af
    ret

prnt_scroll:
    push af
    push hl
    push de
    push bc
    ; Scroll screen up by moving each row up
    ; Read VRAM row by row and shift
    ; Simplified: just clear and home
    ld hl,0
    call set_cursor
    pop bc
    pop de
    pop hl
    pop af
    ret

; Get VDC cursor position into HL
get_cursor:
    push af
    push bc
    ld a,VR_CURHIGH
    call vdc_wreg
    ld c,VDCD & 255
    in a,(c)
    ld h,a
    ld a,VR_CURLOW
    call vdc_wreg
    ld c,VDCD & 255
    in a,(c)
    ld l,a
    pop bc
    pop af
    ret

; Set VDC cursor position from HL
set_cursor:
    push af
    push bc
    ld a,VR_CURHIGH
    call vdc_wreg
    ld a,h
    call vdc_wdat
    ld a,VR_CURLOW
    call vdc_wreg
    ld a,l
    call vdc_wdat
    pop bc
    pop af
    ret

; MSG - Print string at DE, terminated by $0D (not executed)
compat_msg:
    push af
    push hl
    ex de,hl
cm_l:
    ld a,(hl)
    cp $0D
    jr z,cm_done
    inc hl
    call compat_prnt
    jr cm_l
cm_done:
    pop hl
    pop af
    ret

; LISTL - Like MSG but display control codes literally
compat_listl:
    push af
    push hl
    ex de,hl
cl_l:
    ld a,(hl)
    cp $0D
    jr z,cl_done
    inc hl
    cp ' '
    jr c,cl_ctrl
    call compat_prnt
    jr cl_l
cl_ctrl:
    ; Display control code as symbol
    push hl
    push af
    ld a,'^'
    call compat_prnt
    pop af
    add a,$40       ; $01 -> 'A', etc.
    call compat_prnt
    pop hl
    jr cl_l
cl_done:
    pop hl
    pop af
    ret

; GETL - Line input
; Input: DE = buffer address
; Output: Line terminated by $0D
compat_getl:
    push af
    push hl
    push bc
    ex de,hl
    ld b,80
cgl_l:
    call getkey
    or a
    jr z,cgl_l
    cp $0D
    jr z,cgl_done
    cp $08
    jr nz,cgl_ch
    ; Backspace
    ld a,b
    cp 80
    jr z,cgl_l
    inc b
    dec hl
    ld a,$08
    call vdc_putc
    jr cgl_l
cgl_ch:
    cp ' '
    jr c,cgl_l
    ld (hl),a
    inc hl
    dec b
    jr z,cgl_done
    call vdc_putc
    jr cgl_l
cgl_done:
    ld (hl),$0D
    inc hl
    ld (hl),0
    pop bc
    pop hl
    pop af
    ret

; GETKY - Key input
; Returns A = ASCII or 0 if no key
compat_getky:
    call getkey
    or a
    ret nz
    ; Wait for a key
cgky_l:
    push af
    call getkey
    or a
    jr z,cgky_l
    ret

; BRKEY / BRKTST - Break key test
; Returns Z flag if SHIFT+BREAK pressed
compat_brkey:
    push bc
    push hl
    ; Check CIA1 for STOP key (C128 Run/Stop = CBM key)
    ; On C128 keyboard, STOP/RUN is at row $FD, column 4
    ld a,$FD
    push bc
    ld c,CIA1A & 255
    out (c),a
    pop bc
    nop
    nop
    push bc
    ld c,CIA1B & 255
    in a,(c)
    pop bc
    cpl
    and $10          ; column 4
    pop hl
    pop bc
    ret

; Tape not available - return with error
compat_notape:
    scf
    ret

; DIGASC - convert low nibble of A to ASCII hex
digasc:
    and $0F
    add a,$90
    daa
    adc a,$40
    daa
    ret

; ASCDIG - convert ASCII hex to digit
ascdig:
    cp '0'
    jr c,ad_bad
    cp '9'+1
    jr c,ad_num
    cp 'A'
    jr c,ad_bad
    cp 'F'+1
    jr c,ad_alpha
    cp 'a'
    jr c,ad_bad
    cp 'f'+1
    jr c,ad_alpha2
ad_bad:
    scf
    ret
ad_num:
    sub '0'
    or a
    ret
ad_alpha:
    sub 'A'-10
    or a
    ret
ad_alpha2:
    sub 'a'-10
    or a
    ret

; MOVECU - Cursor control
; A = function code ($C0=scroll, $C1=down, $C2=up, $C3=right,
;     $C4=left, $C5=home, $C6=clear, $C7=del, $C8=ins,
;     $C9=cap, $CA=sml, $CD=CR)
movecu:
    push af
    cp $C1
    jp z,prnt_down
    cp $C2
    jp z,prnt_up
    cp $C3
    jp z,prnt_right
    cp $C4
    jp z,prnt_left
    cp $C5
    jp z,prnt_home
    cp $C6
    jp z,prnt_clear
    cp $CD
    jp z,prnt_cr
    cp $C7
    jp z,mc_del
    pop af
    ret

mc_del:
    push af
    call get_cursor
    dec hl
    call set_cursor
    ld a,' '
    call vdc_putc
    call get_cursor
    dec hl
    call set_cursor
    pop af
    ret

welcome:
    db $0A,"** SHARP MZ-80K MONITOR on C128 Z80 **",$0A,$0A,0
prompt_msg:
    db "# ",0
msg_q:
    db "?",$0A,0
msg_bad:
    db "BAD ARG",$0A,0
msg_m:
    db ":",$20,0
msg_loading:
    db "LOAD...",$0A,0
help_txt:
    db "GO MZ Commands:",$0A
    db " D<addr> - Hex dump",$0A
    db " M<addr> - Modify memory",$0A
    db " G<addr> - Execute (Go)",$0A
    db " B       - SP-5025 BASIC",$0A
    db " H       - Help",$0A,0

; ===== SPEAKER/SID DRIVER =====
; Copied to $7F00 at startup. Switches MMU to config 15 (I/O at $D000)
; to access the SID, then restores the original MMU config.

SID_PLAY equ $7F00
SID_STOP equ SID_PLAY + (sid_play_end - sid_driver_start)

sid_driver_start:
sid_play:
    ld a,($FF00)
    push af
    ld a,$0F
    ld ($FF00),a
    ld a,$B4
    ld ($D400),a
    ld a,$0E
    ld ($D401),a
    ld a,$11
    ld ($D404),a
    ld a,$0F
    ld ($D418),a
    pop af
    ld ($FF00),a
    ret
sid_play_end:
sid_stop:
    ld a,($FF00)
    push af
    ld a,$0F
    ld ($FF00),a
    ld a,$10
    ld ($D404),a
    ld a,$00
    ld ($D418),a
    pop af
    ld ($FF00),a
    ret
sid_driver_end:

; ===== COMPATIBILITY HANDLERS =====

compat_sndout:
    jp SID_PLAY

compat_sndstop:
    jp SID_STOP

; ===== VARIABLES =====

ibuf:    ds 64,0
d_adr:   dw 0
s_st:    dw 0
s_en:    dw 0
s_ex:    dw 0
