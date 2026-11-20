# Native ELKS ia16 compiler and stock matching elks-libc must be on PATH.
CC = ia16-elf-gcc
OUT ?= build
CFLAGS = -Os -march=i8086 -mtune=i8086 -mcmodel=small -melks-libc -mregparmcall -Wall -Wextra
all: $(OUT)/buddy160
$(OUT)/buddy160: buddy.c backend.c backend.h runs.S
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) -maout-heap=0x6000 -maout-stack=0x1000 buddy.c backend.c runs.S -o $@
# Original GPL synthetic WZR1 clip; the movie is identical for DOS and ELKS.
# Copy buddy160 and demo/MOVIE.WZD to ELKS; run buddy160 [-p] MOVIE.WZD.
# -p is opt-in, at most 60K frame data, with startup cost reported separately.
demo:
	mkdir -p $(OUT)
	python3 ../Cga/DEMO.PY $(OUT)/demo
.PHONY: all demo
