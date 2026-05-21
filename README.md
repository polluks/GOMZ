# MZ80K-C128 - Sharp MZ-80K Monitor Port for Commodore 128

Ports the Sharp MZ-80K machine code monitor to the Commodore 128's
Z80 coprocessor (no CP/M needed). Runs bare-metal on the C128 Z80.

## Architecture

- **6502 Boot Loader** (`build.py` generates `src/mzboot.s`):
  C128 PRG that initializes VDC (40x25), uploads font, copies Z80
  code to $C000, sets Z80 vector at $FFF0, and switches to Z80.

- **Z80 Monitor** (`src/mzmon.asm`):
  Runs at $C000 on the C128 Z80. Implements MZ-80K monitor
  commands (D=hex dump, M=modify, G=go, L=load tape, H=help).
  Uses Z80 I/O ports for VDC ($D600-$D601) and CIA ($DC00-$DC01).

## Build

Requires vasm (both vasmz80_oldstyle and vasm6502_mot):
```
(vasm built from http://sun.hasenbraten.de/vasm/)
python3 build.py
```

Output: `build/mz80k_c128.prg`

## Usage on C128

1. Transfer `mz80k_c128.prg` to a C128 disk or emulator
2. `BLOAD "MZ80K_C128",8,1`
3. `SYS 7168`

## References

- https://www.idealine.info/sharpmz/mz-80k/dldos.htm (SP-5025 BASIC)
- https://github.com/polluks/trsdos (C128 Z80 boot reference)
- http://www.sharpmz.net/ (MZ-80K technical info)
- https://original.sharpmz.org/mz-80k/download/80kmoni.zip (SP-1002 monitor ROM)
