# Native ELKS ia16 compiler and stock matching elks-libc must be on PATH.
CC = ia16-elf-gcc
OUT ?= build
CFLAGS = -Os -march=i8086 -mtune=i8086 -mcmodel=small -melks-libc -mregparmcall -Wall -Wextra
all: $(OUT)/buddy160
$(OUT)/buddy160: buddy.c backend.c backend.h
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) -maout-heap=0x6000 -maout-stack=0x1000 buddy.c backend.c -o $@
.PHONY: all
