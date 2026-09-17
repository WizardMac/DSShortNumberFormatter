DSShortNumberFormatter
======================

Locale-aware NSNumberFormatter subclass for formatting compact numbers (e.g. "12K" for 12,000).

Usage is the same as a normal NSNumberFormatter. Both directions work: `stringFromNumber:` produces the compact form and `numberFromString:` parses it back ("1.5M" gives 1,500,000). Percent and scientific styles are passed through unchanged.

Installation
------------

Copy DSShortNumberFormatter.m, DSShortNumberFormatter.h, and patterns.plist into your Xcode project. The formatter compiles with or without ARC and requires macOS 10.12 or iOS 10.

patterns.plist holds the compact-number patterns for every locale, extracted from the Unicode Common Locale Data Repository (CLDR). The copy in this repository is generated from CLDR 48.

Regenerating patterns.plist
---------------------------

Download and unzip a CLDR "core" release from https://unicode.org/Public/cldr/ and run:

    make patterns.plist CLDR=/path/to/core

Tests
-----

    make test

This builds the tests in tests/test.m with and without ARC and runs them against patterns.plist.
