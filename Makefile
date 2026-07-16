CC = clang
CFLAGS = -Wall -Wextra -O2

# sdl2-compat via Homebrew doesn't sit on the default pkg-config search path.
SDL_CFLAGS := $(shell PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH" pkg-config --cflags sdl2 2>/dev/null || sdl2-config --cflags)
SDL_LIBS   := $(shell PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$$PKG_CONFIG_PATH" pkg-config --libs sdl2 2>/dev/null || sdl2-config --libs)

BIN = chip8emu

all: $(BIN)

$(BIN): build/chip8_core.o build/chip8.o build/main.o
	$(CC) $^ -o $@ $(SDL_LIBS)

build/chip8_core.o: src/chip8_core.s | build
	$(CC) -c $< -o $@

build/chip8.o: src/chip8.c src/chip8.h | build
	$(CC) $(CFLAGS) -c $< -o $@

build/main.o: src/main.c src/chip8.h | build
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -c $< -o $@

build:
	mkdir -p build

tools/make_test_rom: tools/make_test_rom.c
	$(CC) -o $@ $<

assets/test.ch8: tools/make_test_rom
	./tools/make_test_rom

# Headless proof-of-execution: runs the hand-written test ROM for a fixed
# number of cycles and dumps a BMP screenshot + ASCII framebuffer, no
# display required (falls back to SDL's dummy video driver).
verify: $(BIN) assets/test.ch8
	mkdir -p out
	SDL_VIDEODRIVER=dummy ./$(BIN) assets/test.ch8 --cycles 30 \
		--dump-bmp out/test_screenshot.bmp --dump-ascii out/test_ascii.txt
	cat out/test_ascii.txt

clean:
	rm -rf build $(BIN) tools/make_test_rom out

.PHONY: all clean verify
