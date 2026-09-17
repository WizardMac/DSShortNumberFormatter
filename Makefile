CC = xcrun clang
SDK = $(shell xcrun --show-sdk-path)
CFLAGS = -isysroot $(SDK) -Wall -Wno-deprecated-declarations

# Path to an unzipped CLDR "core" release (https://unicode.org/Public/cldr/).
# Override on the command line: make patterns.plist CLDR=/path/to/core
CLDR ?= $(HOME)/Downloads/core

all: patterns.plist

bin/extract_patterns: src/extract_patterns.c
	mkdir -p bin
	$(CC) $(CFLAGS) -o $@ $< -framework CoreFoundation -lexpat

patterns.plist: bin/extract_patterns
	./bin/extract_patterns $(CLDR) > $@

# Builds the test program with and without ARC and runs both against patterns.plist.
test: build/test-arc build/test-mrc
	cp patterns.plist build/
	./build/test-arc
	./build/test-mrc

build/test-arc: tests/test.m DSShortNumberFormatter.m DSShortNumberFormatter.h
	mkdir -p build
	$(CC) $(CFLAGS) -fobjc-arc -I. -o $@ tests/test.m DSShortNumberFormatter.m -framework Foundation

build/test-mrc: tests/test.m DSShortNumberFormatter.m DSShortNumberFormatter.h
	mkdir -p build
	$(CC) $(CFLAGS) -fno-objc-arc -I. -o $@ tests/test.m DSShortNumberFormatter.m -framework Foundation

clean:
	rm -rf bin build

.PHONY: all test clean
