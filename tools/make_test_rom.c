/* Emits a tiny hand-written CHIP-8 test ROM to assets/test.ch8.
 *
 * What it does when run in the emulator: draws the digits "0 1 2" using the
 * built-in font sprites (LD Vx,byte / LD F,Vx / DRW), exercises ADD Vx,byte
 * and SE Vx,byte (conditional skip -- the skipped instruction is a CLS that
 * would wipe the digits already drawn if the skip were buggy, making the
 * skip a *visible* self-check, not just a register side effect), then
 * exercises CALL/RET by jumping to a subroutine that draws digit "3" and
 * returns into an infinite JP self-loop (halt).
 *
 * Expected final framebuffer: the digits "0123" drawn left to right at
 * (x=2,10,18,26 y=2) using the CHIP-8 5x4 font glyphs.
 *
 * Addresses assume the ROM is loaded at 0x200 (CHIP8_ROM_START), which is
 * exactly what chip8_load_rom() does.
 */
#include <stdio.h>
#include <stdint.h>

static const uint16_t PROGRAM[] = {
    0x6000, // 0x200: LD V0, 0            ; digit '0'
    0xF029, // 0x202: LD F, V0            ; I = font sprite for V0
    0x6102, // 0x204: LD V1, 2            ; x = 2
    0x6202, // 0x206: LD V2, 2            ; y = 2
    0xD125, // 0x208: DRW V1, V2, 5       ; draw digit 0
    0x6001, // 0x20A: LD V0, 1            ; digit '1'
    0xF029, // 0x20C: LD F, V0
    0x610A, // 0x20E: LD V1, 10           ; x = 10
    0xD125, // 0x210: DRW V1, V2, 5       ; draw digit 1
    0x6002, // 0x212: LD V0, 2            ; digit '2'
    0xF029, // 0x214: LD F, V0
    0x6112, // 0x216: LD V1, 18           ; x = 18
    0xD125, // 0x218: DRW V1, V2, 5       ; draw digit 2
    0x7003, // 0x21A: ADD V0, 3           ; V0 = 2+3 = 5
    0x3005, // 0x21C: SE V0, 5            ; true -> skip next instruction
    0x00E0, // 0x21E: CLS                 ; MUST be skipped (would erase 0,1,2 if not)
    0x6309, // 0x220: LD V3, 9            ; marker (proves fall-through reached)
    0x2226, // 0x222: CALL 0x226          ; call digit-3 subroutine
    0x1224, // 0x224: JP 0x224            ; infinite self-loop (halt), reached via RET
    0x6003, // 0x226: LD V0, 3            ; digit '3'  <- subroutine start
    0xF029, // 0x228: LD F, V0
    0x611A, // 0x22A: LD V1, 26           ; x = 26
    0xD125, // 0x22C: DRW V1, V2, 5       ; draw digit 3
    0x00EE, // 0x22E: RET
};

int main(void) {
    const char *path = "assets/test.ch8";
    FILE *f = fopen(path, "wb");
    if (!f) { perror("fopen"); return 1; }
    size_t n = sizeof(PROGRAM) / sizeof(PROGRAM[0]);
    for (size_t i = 0; i < n; i++) {
        uint8_t bytes[2] = { (uint8_t)(PROGRAM[i] >> 8), (uint8_t)(PROGRAM[i] & 0xFF) };
        fwrite(bytes, 1, 2, f);
    }
    fclose(f);
    printf("Wrote %zu bytes (%zu instructions) to %s\n", n * 2, n, path);
    return 0;
}
