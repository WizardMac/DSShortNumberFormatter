DSShortNumberFormatter
======================

Locale-aware NSNumberFormatter subclass for formatting compact numbers (e.g. "12K" for 12,000).

This library requires a copy of the Unicode Common Locale Data Repository (CLDR):

http://cldr.unicode.org/index/downloads

Once you download and unzip a release, edit the Makefile in this directory to point to the CLDR "core" directory. Then type "make" to generate a patterns.plist file.

Now you can install by copying DSShortNumberFormatter.m, DSShortNumberFormatter.h, and patterns.plist into your Xcode project.

Usage is the same as a normal NSNumberFormatter.
