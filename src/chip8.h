#ifndef CHIP8_H
#define CHIP8_H

#include <stdint.h>

#define CHIP8_MEM_SIZE   4096
#define CHIP8_NUM_REGS   16
#define CHIP8_STACK_SIZE 16
#define CHIP8_NUM_KEYS   16
#define CHIP8_WIDTH      64
#define CHIP8_HEIGHT     32
#define CHIP8_GFX_SIZE   (CHIP8_WIDTH * CHIP8_HEIGHT)
#define CHIP8_ROM_START  0x200
#define CHIP8_FONT_START 0x50

/* Layout is deliberately explicit and offsetof-verified (see tools/dump_offsets.c)
 * because the AArch64 core (chip8_core.s) indexes into this struct with raw
 * byte offsets — there is no shared header between C and asm. */
typedef struct {
    uint8_t  memory[CHIP8_MEM_SIZE];
    uint16_t stack[CHIP8_STACK_SIZE];
    uint8_t  V[CHIP8_NUM_REGS];
    uint8_t  gfx[CHIP8_GFX_SIZE];      /* one byte per pixel, 0 or 1 */
    uint8_t  keypad[CHIP8_NUM_KEYS];   /* one byte per key, 0 or 1 */
    uint16_t I;
    uint16_t pc;
    uint16_t sp;
    uint8_t  delay_timer;
    uint8_t  sound_timer;
    uint8_t  draw_flag;
    uint8_t  waiting_for_key;
    uint8_t  wait_key_reg;
    uint8_t  _pad;
    uint32_t rng_state;
} chip8_t;

/* Hand-written AArch64 assembly core (src/chip8_core.s) */
extern void emulate_cycle(chip8_t *cpu);

void chip8_init(chip8_t *cpu);
int  chip8_load_rom(chip8_t *cpu, const char *path);

#endif
