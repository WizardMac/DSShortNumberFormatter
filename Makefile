CC=clang
FOLDER=/Users/emiller/Downloads/core

all:
	$(CC) -o bin/extract_patterns src/extract_patterns.c -framework CoreFoundation -lexpat
	./bin/extract_patterns $(FOLDER) > patterns.plist
