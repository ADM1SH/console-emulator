/* Prints byte offsets of every chip8_t field, and the struct size.
 * Run once when the struct changes; copy the numbers into the .equ
 * constants at the top of src/chip8_core.s. */
#include <stdio.h>
#include <stddef.h>
#include "../src/chip8.h"

int main(void) {
    printf("MEMORY_OFF   = %zu\n", offsetof(chip8_t, memory));
    printf("STACK_OFF    = %zu\n", offsetof(chip8_t, stack));
    printf("V_OFF        = %zu\n", offsetof(chip8_t, V));
    printf("GFX_OFF      = %zu\n", offsetof(chip8_t, gfx));
    printf("KEYPAD_OFF   = %zu\n", offsetof(chip8_t, keypad));
    printf("I_OFF        = %zu\n", offsetof(chip8_t, I));
    printf("PC_OFF       = %zu\n", offsetof(chip8_t, pc));
    printf("SP_OFF       = %zu\n", offsetof(chip8_t, sp));
    printf("DELAY_OFF    = %zu\n", offsetof(chip8_t, delay_timer));
    printf("SOUND_OFF    = %zu\n", offsetof(chip8_t, sound_timer));
    printf("DRAWFLAG_OFF = %zu\n", offsetof(chip8_t, draw_flag));
    printf("WAITKEY_OFF  = %zu\n", offsetof(chip8_t, waiting_for_key));
    printf("WAITREG_OFF  = %zu\n", offsetof(chip8_t, wait_key_reg));
    printf("RNG_OFF      = %zu\n", offsetof(chip8_t, rng_state));
    printf("STRUCT_SIZE  = %zu\n", sizeof(chip8_t));
    return 0;
}
