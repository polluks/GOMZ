# GO MZ - Sharp MZ-80K Monitor Port for Commodore 128

Ports the Sharp MZ-80K machine code monitor (with SP-5025 BASIC)
to the Commodore 128's Z80 coprocessor (no CP/M needed).

## Architecture

- **6502 Boot Loader** (`src/mzboot.mot`):
  C128 PRG (BLOAD at $1C00) that copies Z80 monitor to $C000,
  SP-5025 BASIC to $8000, font to VDC VRAM, and switches to Z80.

- **Z80 Monitor** (`src/mzmon.asm`):
  Runs at $C000. Commands: D=hex dump, M=modify, G=go, B=BASIC,
  H=help. Uses Z80 I/O ports for VDC ($D600-$D601) and CIA
  ($DC00-$DC01).

- **SP-5025 BASIC** (`src/sp5025.bin`):
  Sharp MZ-80K BASIC, stored at $8000 and copied to $1200 on demand.
  Runs via SP-1002 compatibility stubs (PRNT, GETKY, GETL, MSG, etc.)

## Build

Requires vasm (vasmz80_oldstyle and vasm6502_mot) and exomizer:
```
python3 build.py
```

Output:
```
build/mz80k_c128.prg       (17038 bytes  - uncompressed)
build/mz80k_c128_exo.prg   (10976 bytes  - exomizer self-extracting)
```

## Usage on C128

Transfer a PRG to disk or emulator, then:

```
BLOAD"MZ80K_C128",8,1 : SYS 7168
BOOT"MZ80K_C128_EXO"
```

## Monitor Commands

| Key | Command |
|-----|---------|
| D | Hex dump (D<addr> or D<start> <end>) |
| M | Modify memory (M<addr> <byte> <byte> ...) |
| G | Execute at address (G<addr>) |
| B | Start SP-5025 BASIC |
| H | Help |

## References

- https://www.idealine.info/sharpmz/mz-80k/dldos.htm (SP-5025 BASIC)
- https://github.com/polluks/trsdos (C128 Z80 boot reference)
- http://www.sharpmz.net/ (MZ-80K technical info)
- https://original.sharpmz.org/mz-80k/download/80kmoni.zip (SP-1002 monitor ROM)
- https://github.com/psychotimmy/sharpmz-80k (Sharp MZ-80K reference)
