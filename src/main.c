// CHIP-8 driver: memory/ROM setup, SDL2 window + framebuffer, keypad input,
// ~60Hz timer tick. The actual CPU (fetch/decode/execute) lives in
// chip8_core.s and is called once per emulated cycle as emulate_cycle().
#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "chip8.h"

#define SCALE 12
#define CYCLES_PER_FRAME 10 // ~600Hz CPU at 60Hz frame/timer rate

// Standard CHIP-8 keypad -> QWERTY mapping:
//   1 2 3 C        1 2 3 4
//   4 5 6 D   ->   Q W E R
//   7 8 9 E        A S D F
//   A 0 B F        Z X C V
static const SDL_Scancode KEYMAP[16] = {
    SDL_SCANCODE_X, SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3,
    SDL_SCANCODE_Q, SDL_SCANCODE_W, SDL_SCANCODE_E, SDL_SCANCODE_A,
    SDL_SCANCODE_S, SDL_SCANCODE_D, SDL_SCANCODE_Z, SDL_SCANCODE_C,
    SDL_SCANCODE_4, SDL_SCANCODE_R, SDL_SCANCODE_F, SDL_SCANCODE_V,
};

static void render_gfx_to_pixels(const chip8_t *cpu, uint32_t *pixels) {
    for (int y = 0; y < CHIP8_HEIGHT; y++) {
        for (int x = 0; x < CHIP8_WIDTH; x++) {
            uint32_t color = cpu->gfx[y * CHIP8_WIDTH + x] ? 0xFFFFFFFFu : 0xFF101018u;
            for (int sy = 0; sy < SCALE; sy++) {
                int py = y * SCALE + sy;
                uint32_t *row = pixels + (size_t)py * CHIP8_WIDTH * SCALE;
                for (int sx = 0; sx < SCALE; sx++) {
                    row[x * SCALE + sx] = color;
                }
            }
        }
    }
}

static void dump_ascii(const chip8_t *cpu, FILE *out) {
    for (int y = 0; y < CHIP8_HEIGHT; y++) {
        for (int x = 0; x < CHIP8_WIDTH; x++) {
            fputc(cpu->gfx[y * CHIP8_WIDTH + x] ? '#' : '.', out);
        }
        fputc('\n', out);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
            "usage: %s <rom.ch8> [--cycles N] [--dump-bmp path.bmp] [--dump-ascii path.txt]\n",
            argv[0]);
        return 1;
    }
    const char *rom_path = argv[1];
    long fixed_cycles = -1; // -1 = run interactively forever
    const char *dump_bmp_path = NULL;
    const char *dump_ascii_path = NULL;

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--cycles") == 0 && i + 1 < argc) {
            fixed_cycles = atol(argv[++i]);
        } else if (strcmp(argv[i], "--dump-bmp") == 0 && i + 1 < argc) {
            dump_bmp_path = argv[++i];
        } else if (strcmp(argv[i], "--dump-ascii") == 0 && i + 1 < argc) {
            dump_ascii_path = argv[++i];
        }
    }

    chip8_t cpu;
    chip8_init(&cpu);
    if (chip8_load_rom(&cpu, rom_path) != 0) {
        return 1;
    }

    // Headless-safe init: try the real video driver, fall back to the
    // "dummy" driver (no window server needed) so this still runs and
    // produces a BMP/ASCII proof in a sandbox with no display attached.
    int have_display = 1;
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init video failed (%s), falling back to dummy driver\n", SDL_GetError());
        SDL_setenv("SDL_VIDEODRIVER", "dummy", 1);
        have_display = 0;
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            fprintf(stderr, "SDL_Init dummy driver also failed: %s\n", SDL_GetError());
            return 1;
        }
    }

    SDL_Window *window = SDL_CreateWindow(
        "CHIP-8", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        CHIP8_WIDTH * SCALE, CHIP8_HEIGHT * SCALE, SDL_WINDOW_SHOWN);
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed (%s), continuing headless\n", SDL_GetError());
        have_display = 0;
    }

    SDL_Renderer *renderer = NULL;
    SDL_Texture *texture = NULL;
    if (window) {
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
        if (renderer) {
            texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                         SDL_TEXTUREACCESS_STREAMING,
                                         CHIP8_WIDTH * SCALE, CHIP8_HEIGHT * SCALE);
        }
        if (!renderer || !texture) {
            fprintf(stderr, "SDL renderer/texture creation failed (%s), continuing headless\n", SDL_GetError());
            have_display = 0;
        }
    }

    uint32_t *pixels = malloc((size_t)CHIP8_WIDTH * SCALE * CHIP8_HEIGHT * SCALE * sizeof(uint32_t));

    int running = 1;
    long total_cycles = 0;
    while (running) {
        if (window) {
            SDL_Event e;
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) running = 0;
                if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) {
                    uint8_t down = (e.type == SDL_KEYDOWN);
                    for (int k = 0; k < 16; k++) {
                        if (e.key.keysym.scancode == KEYMAP[k]) cpu.keypad[k] = down;
                    }
                    if (e.key.keysym.scancode == SDL_SCANCODE_ESCAPE) running = 0;
                }
            }
        }

        for (int c = 0; c < CYCLES_PER_FRAME; c++) {
            emulate_cycle(&cpu);
            total_cycles++;
            if (fixed_cycles >= 0 && total_cycles >= fixed_cycles) { running = 0; break; }
        }

        if (cpu.delay_timer > 0) cpu.delay_timer--;
        if (cpu.sound_timer > 0) cpu.sound_timer--; // no audio output (see README)

        if (cpu.draw_flag && pixels) {
            render_gfx_to_pixels(&cpu, pixels);
            cpu.draw_flag = 0;
            if (texture && renderer) {
                SDL_UpdateTexture(texture, NULL, pixels, CHIP8_WIDTH * SCALE * sizeof(uint32_t));
                SDL_RenderClear(renderer);
                SDL_RenderCopy(renderer, texture, NULL, NULL);
                SDL_RenderPresent(renderer);
            }
        }

        if (window && have_display) SDL_Delay(16); // ~60Hz frame pacing
    }

    // Proof-of-execution dump: BMP screenshot (works headless too, since the
    // pixel buffer is rendered independently of the window) and/or ASCII art.
    if (dump_bmp_path && pixels) {
        SDL_Surface *surf = SDL_CreateRGBSurfaceWithFormatFrom(
            pixels, CHIP8_WIDTH * SCALE, CHIP8_HEIGHT * SCALE,
            32, CHIP8_WIDTH * SCALE * 4, SDL_PIXELFORMAT_ARGB8888);
        if (surf) {
            SDL_SaveBMP(surf, dump_bmp_path);
            SDL_FreeSurface(surf);
            fprintf(stderr, "Wrote screenshot to %s\n", dump_bmp_path);
        }
    }
    if (dump_ascii_path) {
        FILE *f = fopen(dump_ascii_path, "w");
        if (f) {
            dump_ascii(&cpu, f);
            fclose(f);
            fprintf(stderr, "Wrote ASCII dump to %s\n", dump_ascii_path);
        }
    }

    free(pixels);
    if (texture) SDL_DestroyTexture(texture);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
