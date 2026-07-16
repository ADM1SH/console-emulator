// chip8_core.s -- CHIP-8 fetch/decode/execute core, hand-written AArch64 (Apple Silicon).
//
// void emulate_cycle(chip8_t *cpu);
//
// Struct offsets below are copied from `tools/dump_offsets.c` output (offsetof on
// the real chip8_t in src/chip8.h) -- if the struct changes, re-run that tool and
// update these .equ values.
//
// Register convention used throughout this function (all live for the whole call):
//   x19 = cpu pointer                 (== &cpu->memory[0], MEMORY_OFF is 0)
//   w20 = current 16-bit opcode
//   x21 = X nibble (opcode bits 11-8) = register index, also loop-safe 64-bit
//   x22 = Y nibble (opcode bits 7-4)
//   x24 = &cpu->V[0]
//   x25 = &cpu->gfx[0]
//   x26 = &cpu->keypad[0]
//   x27 = &cpu->stack[0]
//   x28 = &cpu->delay_timer  (delay/sound/draw_flag/waiting_for_key/wait_key_reg
//                              are 5 contiguous bytes, so this one base covers all 5)
// x0-x18 are scratch, free to clobber inside opcode handlers (no calls are made).

.equ MEMORY_OFF,   0
.equ STACK_OFF,    4096
.equ V_OFF,        4128
.equ GFX_OFF,      4144
.equ KEYPAD_OFF,   6192
.equ I_OFF,        6208
.equ PC_OFF,       6210
.equ SP_OFF,       6212
.equ DELAY_OFF,    6214   // = x28 + 0
.equ SOUND_OFF,    6215   // = x28 + 1
.equ DRAWFLAG_OFF, 6216   // = x28 + 2
.equ WAITKEY_OFF,  6217   // = x28 + 3
.equ WAITREG_OFF,  6218   // = x28 + 4
.equ RNG_OFF,      6220

.equ FONT_START,   0x50

.text
.global _emulate_cycle
.p2align 2
_emulate_cycle:
    // ---- prologue: save callee-saved regs we use as persistent bases ----
    stp x29, x30, [sp, -96]!
    mov x29, sp
    stp x19, x20, [sp, 16]
    stp x21, x22, [sp, 32]
    stp x23, x24, [sp, 48]
    stp x25, x26, [sp, 64]
    stp x27, x28, [sp, 80]

    mov x19, x0                  // cpu pointer

    mov w9, #V_OFF
    add x24, x19, x9             // x24 = &V[0]
    mov w9, #GFX_OFF
    add x25, x19, x9             // x25 = &gfx[0]
    mov w9, #KEYPAD_OFF
    add x26, x19, x9             // x26 = &keypad[0]
    mov w9, #STACK_OFF
    add x27, x19, x9             // x27 = &stack[0]
    mov w9, #DELAY_OFF
    add x28, x19, x9             // x28 = &delay_timer (timers/flags cluster base)

    // ---- FX0A wait-for-key handling: if waiting, this cycle only scans keys ----
    ldrb w9, [x28, #3]           // waiting_for_key
    cbz w9, Lfetch

    mov x10, #0                  // key index scan
Lscan_loop:
    cmp x10, #16
    b.ge Ldone                   // no key pressed yet -- idle this cycle
    ldrb w12, [x26, x10]
    cbnz w12, Lkey_found
    add x10, x10, #1
    b Lscan_loop
Lkey_found:
    ldrb w13, [x28, #4]          // wait_key_reg
    strb w10, [x24, x13]         // V[wait_key_reg] = key index
    strb wzr, [x28, #3]          // waiting_for_key = 0
    b Ldone

    // ---- fetch ----
Lfetch:
    ldrh w9, [x19, #PC_OFF]      // w9 = pc
    ldrb w11, [x19, x9]          // high byte = memory[pc]   (memory base = x19)
    add x12, x9, #1
    ldrb w13, [x19, x12]         // low byte = memory[pc+1]
    orr w20, w13, w11, lsl #8    // opcode = (high<<8)|low
    add w9, w9, #2
    strh w9, [x19, #PC_OFF]      // pc += 2 (jumps/calls overwrite below)

    // ---- decode common nibbles ----
    lsr w21, w20, #8
    and w21, w21, #0xF           // X
    lsr w22, w20, #4
    and w22, w22, #0xF           // Y

    // ---- dispatch on top nibble ----
    lsr w9, w20, #12
    cmp w9, #0x0
    b.eq L_op0
    cmp w9, #0x1
    b.eq L_JP
    cmp w9, #0x2
    b.eq L_CALL
    cmp w9, #0x3
    b.eq L_SE_VX_KK
    cmp w9, #0x4
    b.eq L_SNE_VX_KK
    cmp w9, #0x5
    b.eq L_SE_VX_VY
    cmp w9, #0x6
    b.eq L_LD_VX_KK
    cmp w9, #0x7
    b.eq L_ADD_VX_KK
    cmp w9, #0x8
    b.eq L_op8
    cmp w9, #0x9
    b.eq L_SNE_VX_VY
    cmp w9, #0xA
    b.eq L_LD_I_NNN
    cmp w9, #0xB
    b.eq L_JP_V0_NNN
    cmp w9, #0xC
    b.eq L_RND
    cmp w9, #0xD
    b.eq L_DRW
    cmp w9, #0xE
    b.eq L_opE
    cmp w9, #0xF
    b.eq L_opF
    b Ldone                      // unknown opcode -- ignore

// ============================== 0x0___ ==============================
L_op0:
    cmp w20, #0x00E0
    b.eq L_CLS
    cmp w20, #0x00EE
    b.eq L_RET
    b Ldone                      // 0nnn SYS addr -- ignored (no real machine to call)

L_CLS:
    mov x9, #0
1:
    cmp x9, #2048
    b.ge 2f
    strb wzr, [x25, x9]
    add x9, x9, #1
    b 1b
2:
    mov w9, #1
    strb w9, [x28, #2]           // draw_flag = 1
    b Ldone

L_RET:
    ldrh w9, [x19, #SP_OFF]
    sub w9, w9, #1
    strh w9, [x19, #SP_OFF]
    lsl x10, x9, #1
    ldrh w11, [x27, x10]
    strh w11, [x19, #PC_OFF]
    b Ldone

// ============================== 1nnn / 2nnn ==============================
L_JP:
    and w9, w20, #0x0FFF
    strh w9, [x19, #PC_OFF]
    b Ldone

L_CALL:
    ldrh w9, [x19, #SP_OFF]
    lsl x10, x9, #1
    ldrh w11, [x19, #PC_OFF]     // return address (pc already advanced past CALL)
    strh w11, [x27, x10]
    add w9, w9, #1
    strh w9, [x19, #SP_OFF]
    and w9, w20, #0x0FFF
    strh w9, [x19, #PC_OFF]
    b Ldone

// ============================== 3xkk / 4xkk / 5xy0 / 9xy0 ==============================
L_SE_VX_KK:
    ldrb w9, [x24, x21]
    and w10, w20, #0xFF
    cmp w9, w10
    b.ne Ldone
    b Lskip_next

L_SNE_VX_KK:
    ldrb w9, [x24, x21]
    and w10, w20, #0xFF
    cmp w9, w10
    b.eq Ldone
    b Lskip_next

L_SE_VX_VY:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    cmp w9, w10
    b.ne Ldone
    b Lskip_next

L_SNE_VX_VY:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    cmp w9, w10
    b.eq Ldone
    b Lskip_next

Lskip_next:
    ldrh w11, [x19, #PC_OFF]
    add w11, w11, #2
    strh w11, [x19, #PC_OFF]
    b Ldone

// ============================== 6xkk / 7xkk ==============================
L_LD_VX_KK:
    and w9, w20, #0xFF
    strb w9, [x24, x21]
    b Ldone

L_ADD_VX_KK:
    ldrb w9, [x24, x21]
    and w10, w20, #0xFF
    add w9, w9, w10
    strb w9, [x24, x21]           // no carry flag for this form (per spec)
    b Ldone

// ============================== 8xy_ ==============================
L_op8:
    and w9, w20, #0xF
    cmp w9, #0x0
    b.eq L_LD_VX_VY
    cmp w9, #0x1
    b.eq L_OR
    cmp w9, #0x2
    b.eq L_AND
    cmp w9, #0x3
    b.eq L_XOR
    cmp w9, #0x4
    b.eq L_ADD_VX_VY
    cmp w9, #0x5
    b.eq L_SUB
    cmp w9, #0x6
    b.eq L_SHR
    cmp w9, #0x7
    b.eq L_SUBN
    cmp w9, #0xE
    b.eq L_SHL
    b Ldone

L_LD_VX_VY:
    ldrb w9, [x24, x22]
    strb w9, [x24, x21]
    b Ldone

L_OR:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    orr w9, w9, w10
    strb w9, [x24, x21]
    b Ldone

L_AND:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    and w9, w9, w10
    strb w9, [x24, x21]
    b Ldone

L_XOR:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    eor w9, w9, w10
    strb w9, [x24, x21]
    b Ldone

L_ADD_VX_VY:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    add w11, w9, w10
    and w12, w11, #0xFF
    strb w12, [x24, x21]
    cmp w11, #0x100
    b.lt 1f
    mov w13, #1
    b 2f
1:
    mov w13, #0
2:
    strb w13, [x24, #15]          // VF
    b Ldone

L_SUB:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    cmp w9, w10
    b.lt 1f
    mov w13, #1                   // Vx >= Vy: no borrow
    b 2f
1:
    mov w13, #0
2:
    sub w11, w9, w10
    and w11, w11, #0xFF
    strb w11, [x24, x21]
    strb w13, [x24, #15]
    b Ldone

L_SHR:
    ldrb w9, [x24, x21]
    and w13, w9, #1                // LSB -> VF
    lsr w9, w9, #1
    strb w9, [x24, x21]
    strb w13, [x24, #15]
    b Ldone

L_SUBN:
    ldrb w9, [x24, x21]
    ldrb w10, [x24, x22]
    cmp w10, w9
    b.lt 1f
    mov w13, #1
    b 2f
1:
    mov w13, #0
2:
    sub w11, w10, w9
    and w11, w11, #0xFF
    strb w11, [x24, x21]
    strb w13, [x24, #15]
    b Ldone

L_SHL:
    ldrb w9, [x24, x21]
    lsr w13, w9, #7
    and w13, w13, #1                // MSB -> VF
    lsl w9, w9, #1
    and w9, w9, #0xFF
    strb w9, [x24, x21]
    strb w13, [x24, #15]
    b Ldone

// ============================== Annn / Bnnn / Cxkk ==============================
L_LD_I_NNN:
    and w9, w20, #0x0FFF
    strh w9, [x19, #I_OFF]
    b Ldone

L_JP_V0_NNN:
    and w9, w20, #0x0FFF
    ldrb w10, [x24, #0]
    add w9, w9, w10
    strh w9, [x19, #PC_OFF]
    b Ldone

L_RND:
    ldr w9, [x19, #RNG_OFF]        // xorshift32
    eor w9, w9, w9, lsl #13
    eor w9, w9, w9, lsr #17
    eor w9, w9, w9, lsl #5
    str w9, [x19, #RNG_OFF]
    and w10, w20, #0xFF
    and w9, w9, w10
    strb w9, [x24, x21]
    b Ldone

// ============================== Dxyn ==============================
L_DRW:
    and w1, w20, #0xF              // n = sprite height
    ldrb w2, [x24, x21]
    ldrb w3, [x24, x22]
    and w2, w2, #63                // x_coord
    and w3, w3, #31                // y_coord
    mov w10, #0
    strb w10, [x24, #15]           // VF = 0

    mov x4, #0                     // row
L_drw_row:
    cmp x4, x1
    b.ge L_drw_done
    ldrh w9, [x19, #I_OFF]
    add x9, x9, x4
    ldrb w5, [x19, x9]             // sprite_byte

    mov x6, #0                     // col
L_drw_col:
    cmp x6, #8
    b.ge L_drw_col_done
    mov w7, #0x80
    lsr w7, w7, w6
    and w7, w5, w7
    cbz w7, L_drw_col_next

    add w8, w2, w6
    and w8, w8, #63                // px
    add w0, w3, w4
    and w0, w0, #31                // py

    lsl w9, w0, #6
    add w9, w9, w8                 // idx = py*64+px

    ldrb w10, [x25, x9]
    cbz w10, L_drw_no_collision
    mov w11, #1
    strb w11, [x24, #15]
L_drw_no_collision:
    eor w10, w10, #1
    strb w10, [x25, x9]

L_drw_col_next:
    add x6, x6, #1
    b L_drw_col
L_drw_col_done:
    add x4, x4, #1
    b L_drw_row
L_drw_done:
    mov w9, #1
    strb w9, [x28, #2]             // draw_flag = 1
    b Ldone

// ============================== Ex9E / ExA1 ==============================
L_opE:
    and w9, w20, #0xFF
    cmp w9, #0x9E
    b.eq L_SKP
    cmp w9, #0xA1
    b.eq L_SKNP
    b Ldone

L_SKP:
    ldrb w9, [x24, x21]
    ldrb w10, [x26, x9]
    cbz w10, Ldone
    b Lskip_next

L_SKNP:
    ldrb w9, [x24, x21]
    ldrb w10, [x26, x9]
    cbnz w10, Ldone
    b Lskip_next

// ============================== Fx__ ==============================
L_opF:
    and w9, w20, #0xFF
    cmp w9, #0x07
    b.eq L_LD_VX_DT
    cmp w9, #0x0A
    b.eq L_LD_VX_K
    cmp w9, #0x15
    b.eq L_LD_DT_VX
    cmp w9, #0x18
    b.eq L_LD_ST_VX
    cmp w9, #0x1E
    b.eq L_ADD_I_VX
    cmp w9, #0x29
    b.eq L_LD_F_VX
    cmp w9, #0x33
    b.eq L_LD_B_VX
    cmp w9, #0x55
    b.eq L_LD_I_VX
    cmp w9, #0x65
    b.eq L_LD_VX_I
    b Ldone

L_LD_VX_DT:
    ldrb w9, [x28, #0]
    strb w9, [x24, x21]
    b Ldone

L_LD_VX_K:
    mov w9, #1
    strb w9, [x28, #3]             // waiting_for_key = 1
    strb w21, [x28, #4]            // wait_key_reg = X
    b Ldone

L_LD_DT_VX:
    ldrb w9, [x24, x21]
    strb w9, [x28, #0]
    b Ldone

L_LD_ST_VX:
    ldrb w9, [x24, x21]
    strb w9, [x28, #1]
    b Ldone

L_ADD_I_VX:
    ldrh w9, [x19, #I_OFF]
    ldrb w10, [x24, x21]
    add w9, w9, w10
    strh w9, [x19, #I_OFF]
    b Ldone

L_LD_F_VX:
    ldrb w9, [x24, x21]
    mov w10, #5
    mul w9, w9, w10
    mov w11, #FONT_START
    add w9, w9, w11
    strh w9, [x19, #I_OFF]
    b Ldone

L_LD_B_VX:
    ldrb w9, [x24, x21]
    mov w10, #100
    udiv w11, w9, w10               // hundreds
    msub w12, w11, w10, w9          // value - hundreds*100
    mov w10, #10
    udiv w13, w12, w10              // tens
    msub w14, w13, w10, w12         // ones

    ldrh w15, [x19, #I_OFF]
    strb w11, [x19, x15]
    add x16, x15, #1
    strb w13, [x19, x16]
    add x16, x15, #2
    strb w14, [x19, x16]
    b Ldone

L_LD_I_VX:
    ldrh w9, [x19, #I_OFF]
    mov x10, #0
L_ldi_loop:
    cmp x10, x21
    b.gt L_ldi_done
    ldrb w11, [x24, x10]
    add x12, x9, x10
    strb w11, [x19, x12]
    add x10, x10, #1
    b L_ldi_loop
L_ldi_done:
    b Ldone

L_LD_VX_I:
    ldrh w9, [x19, #I_OFF]
    mov x10, #0
L_ldvxi_loop:
    cmp x10, x21
    b.gt L_ldvxi_done
    add x12, x9, x10
    ldrb w11, [x19, x12]
    strb w11, [x24, x10]
    add x10, x10, #1
    b L_ldvxi_loop
L_ldvxi_done:
    b Ldone

// ============================== epilogue ==============================
Ldone:
    ldp x27, x28, [sp, 80]
    ldp x25, x26, [sp, 64]
    ldp x23, x24, [sp, 48]
    ldp x21, x22, [sp, 32]
    ldp x19, x20, [sp, 16]
    ldp x29, x30, [sp], 96
    ret
