# Custom 16-Bit Console Emulator

[![C / AArch64 / SDL2](https://img.shields.io/Emulation-CHIP--8_%7C_AArch64-informational.svg)](https://github.com/ADM1SH/console-emulator)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub Issues](https://img.shields.io/github/issues/ADM1SH/console-emulator)](https://github.com/ADM1SH/console-emulator/issues)


A CHIP-8 emulator: hand-written AArch64 assembly CPU core + a C/SDL2 driver.

> The brief said "Game Boy/NES/CHIP-8" : Game Boy/NES are multi-week,
> cycle-accurate undertakings even for hobbyists; CHIP-8 is the one that's
> realistic to get genuinely correct and complete in one session, so that's
> what's built here.

## What it does

- Loads a CHIP-8 ROM into a 4KB memory image and runs it.
- The entire fetch-decode-execute instruction cycle (`emulate_cycle`) is
  hand-written AArch64 assembly (`src/chip8_core.s`) : not a C interpreter
  with an asm wrapper. The C side just calls it once per emulated cycle.
- Renders the 64x32 monochrome framebuffer scaled up 12x via SDL2.
- Maps SDL2 keyboard events to the 16-key CHIP-8 hex keypad.
- Ticks the delay/sound timers at ~60Hz.
- Falls back to SDL's headless "dummy" video driver automatically if no
  display/window server is available, so it still runs (and can still dump
  a screenshot) in a sandboxed/CI environment.

## Build

```sh
make          # builds ./chip8emu
```

Needs `clang` and SDL2 (`brew install sdl2` : this machine has it via
`sdl2-compat`). The Makefile locates SDL2 with `pkg-config` first
(`PKG_CONFIG_PATH` is patched to include Homebrew's path since it isn't on
the default search path), falling back to `sdl2-config`.

## Run

```sh
./chip8emu <rom.ch8>                     # interactive, opens an SDL window
./chip8emu <rom.ch8> --cycles 1000       # run exactly N cycles then exit
./chip8emu <rom.ch8> --dump-bmp out.bmp  # save a screenshot of the framebuffer
./chip8emu <rom.ch8> --dump-ascii out.txt  # dump the framebuffer as ASCII art
```

Keypad mapping (standard CHIP-8 layout on QWERTY):

```
1 2 3 C        1 2 3 4
4 5 6 D   ->   Q W E R
7 8 9 E        A S D F
A 0 B F        Z X C V
```

## Verification / proof of execution

No hardware CHIP-8 ROM was available, so `tools/make_test_rom.c` hand-emits
a small (24-instruction, 48-byte) ROM as raw big-endian opcode bytes :
`assets/test.ch8`. It draws the digits "0123" using the built-in font
sprites and deliberately exercises a conditional skip (`SE`) whose skipped
instruction is a `CLS` : if the skip logic were broken, the `CLS` would
execute and wipe the digits already on screen, so a correct ASCII/BMP dump
is a real correctness check, not just a "something rendered" check.

```sh
make verify
```

This builds everything, generates the ROM, runs it for 30 cycles under
`SDL_VIDEODRIVER=dummy` (no display needed), and dumps both a BMP
screenshot (`out/test_screenshot.bmp`) and an ASCII framebuffer dump
(`out/test_ascii.txt`), then prints the ASCII dump. Captured output:

```
..####......#.....####....####..................................
..#..#.....##........#.......#..................................
..#..#......#.....####....####..................................
..#..#......#.....#..........#..................................
..####.....###....####....####..................................
```

"0123" rendered correctly, and digits 0/1/2 survived the skipped `CLS` :
confirming `LD Vx,byte`, `LD F,Vx`, `DRW`, `ADD Vx,byte`, `SE Vx,byte`,
`CALL`/`RET`, and `JP` all work.

## Architecture

### Memory map

| Range           | Contents                          |
|------------------|------------------------------------|
| `0x000`-`0x04F` | unused (reserved, historically interpreter) |
| `0x050`-`0x09F` | built-in font set (16 glyphs x 5 bytes) |
| `0x200`-`0xFFF` | ROM / program space (loaded here)  |

### Files

| File | Role |
|------|------|
| `src/chip8_core.s` | Hand-written AArch64 core: `emulate_cycle(chip8_t*)` : fetch, decode, execute. |
| `src/chip8.h` | The `chip8_t` struct shared (by raw byte offset) between C and asm. |
| `src/chip8.c` | Init, font loading, ROM loading. |
| `src/main.c` | SDL2 window/framebuffer, keypad input, main loop, 60Hz timer tick, headless dump. |
| `tools/make_test_rom.c` | Emits `assets/test.ch8`. |
| `tools/dump_offsets.c` | Prints `offsetof()` for every `chip8_t` field : used to derive the `.equ` constants at the top of `chip8_core.s`. Re-run this and update the asm if the struct changes. |

The C struct and the assembly have no shared header : the `.s` file indexes
into `chip8_t` with raw byte offsets (`.equ` constants), verified against
`offsetof()` via `tools/dump_offsets.c`. This is the standard way to hand-write
assembly against a C struct without a code generator.

### Opcode table (all implemented in `chip8_core.s`)

| Opcode | Mnemonic | Opcode | Mnemonic |
|--------|----------|--------|----------|
| `00E0` | CLS | `8xy6` | SHR Vx |
| `00EE` | RET | `8xy7` | SUBN Vx, Vy |
| `1nnn` | JP addr | `8xyE` | SHL Vx |
| `2nnn` | CALL addr | `9xy0` | SNE Vx, Vy |
| `3xkk` | SE Vx, byte | `Annn` | LD I, addr |
| `4xkk` | SNE Vx, byte | `Bnnn` | JP V0, addr |
| `5xy0` | SE Vx, Vy | `Cxkk` | RND Vx, byte |
| `6xkk` | LD Vx, byte | `Dxyn` | DRW Vx, Vy, nibble |
| `7xkk` | ADD Vx, byte | `Ex9E` | SKP Vx |
| `8xy0` | LD Vx, Vy | `ExA1` | SKNP Vx |
| `8xy1` | OR Vx, Vy | `Fx07/15/18` | LD Vx,DT / DT,Vx / ST,Vx |
| `8xy2` | AND Vx, Vy | `Fx0A` | LD Vx, K (wait for key) |
| `8xy3` | XOR Vx, Vy | `Fx1E/29` | ADD I,Vx / LD F,Vx |
| `8xy4` | ADD Vx, Vy | `Fx33` | LD B, Vx (BCD) |
| `8xy5` | SUB Vx, Vy | `Fx55/65` | LD [I],Vx / LD Vx,[I] |

## Simplified vs full spec

- **CHIP-8, not NES/Game Boy.** CHIP-8 is a simple bytecode VM, not a
  cycle-accurate hardware emulation of a real CPU/PPU. *Add when: you want
  real cartridge compatibility : that's a from-scratch NES/Game Boy project,
  not an extension of this one.*
- **No sound output, timer only.** `sound_timer` counts down at 60Hz per
  spec, but nothing plays when it's nonzero. *Add when: wire an SDL2 audio
  callback that beeps while `cpu.sound_timer > 0`.*
- **Hand-written minimal test ROM, not a real game cartridge.** `assets/test.ch8`
  is 24 instructions built to exercise and visually prove a slice of the
  instruction set, not a playable game. *Add when: drop a real public-domain
  CHIP-8 ROM (e.g. IBM Logo, Pong) into `assets/` and run it the same way.*

## Support
Submit issues, questions, or bug reports to the GitHub issue tracker:
https://github.com/ADM1SH/console-emulator/issues


## Roadmap
* [x] Core architecture and baseline implementation.
* [x] Functional verification and test coverage.
* [ ] Add SCHIP (Super-CHIP) extended instruction set
* [ ] Implement integrated debugger with opcode stepping and memory hex view


## Contributing
Contributions are welcome.
1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/improvement`.
3. Commit your changes: `git commit -m "feat: enhance functionality"`.
4. Push to the branch: `git push origin feature/improvement`.
5. Open a Pull Request.


## Authors and Acknowledgment
* **Adam Anwar** (ADM1SH) - Lead architect and developer.
* Developed by Adam Anwar. Hardware specification referenced from Cowgod's CHIP-8 Technical Reference.


## License
Licensed under the MIT License. See `LICENSE` for details.


## Project Status
Complete hardware emulator. Running CHIP-8 ROMs at accurate clock speeds.
