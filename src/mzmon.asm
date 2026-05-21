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

    ; Clear screen
    call vdc_clear

    ; Show banner
    ld hl,welcome
    call vdc_puts

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

badarg:
    ld hl,msg_bad
    call vdc_puts
    ret

; ===== MESSAGES =====

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
    db "MZ80K-C128 Commands:",$0A
    db " D<addr> - Hex dump",$0A
    db " M<addr> - Modify memory",$0A
    db " G<addr> - Execute (Go)",$0A
    db " L       - Load from tape",$0A
    db " S<start> <end> - Save to tape",$0A
    db " H       - Help",$0A,0

; ===== VARIABLES =====

ibuf:    ds 64,0
d_adr:   dw 0
s_st:    dw 0
s_en:    dw 0
s_ex:    dw 0
