/* Regression tests for DSShortNumberFormatter. Run with `make test`.
 * Expected strings follow the CLDR 48 data in patterns.plist. */

#import <Foundation/Foundation.h>
#import "DSShortNumberFormatter.h"

static int failures = 0;

static DSShortNumberFormatter *formatter(NSString *localeIdentifier) {
    DSShortNumberFormatter *f = [[DSShortNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.locale = [NSLocale localeWithLocaleIdentifier:localeIdentifier];
    return f;
}

/* Locale data uses assorted non-breaking spaces; compare them as plain spaces. */
static NSString *normalized(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@" "];
    return [s stringByReplacingOccurrencesOfString:@" " withString:@" "];
}

static void expect(NSString *label, NSString *got, NSString *want) {
    BOOL ok = got == want || [normalized(got) isEqualToString:normalized(want)];
    if (!ok)
        failures++;
    printf("%s  %-28s  got '%s'  want '%s'\n", ok ? "ok  " : "FAIL",
           label.UTF8String, got.UTF8String ?: "(nil)", want.UTF8String ?: "(nil)");
}

#define EXPECT_STRING(f, n, want) \
    expect([NSString stringWithFormat:@"%@ %@", f.locale.localeIdentifier, @(n)], [f stringFromNumber:@(n)], want)
#define EXPECT_NUMBER(f, s, want) \
    expect([NSString stringWithFormat:@"parse '%@'", s], [f numberFromString:s].stringValue, want)

int main(void) {
    @autoreleasepool {
        DSShortNumberFormatter *en = formatter(@"en_US");
        EXPECT_STRING(en, 999, @"999");
        EXPECT_STRING(en, 1500, @"1.5K");
        EXPECT_STRING(en, -1500, @"-1.5K");
        EXPECT_STRING(en, 12000, @"12K");
        EXPECT_STRING(en, 12345, @"12.345K");
        EXPECT_STRING(en, 150000, @"150K");
        EXPECT_STRING(en, 1234567, @"1.235M");
        EXPECT_STRING(en, 2500000000, @"2.5B");
        EXPECT_STRING(en, 1e15, @"1000T");
        EXPECT_STRING(en, 0.5, @"0.5");
        EXPECT_STRING(en, 42.5, @"42.5");

        /* Rounding carries into the next magnitude. */
        EXPECT_STRING(en, 999999.9, @"1M");
        EXPECT_STRING(en, 999999.9999, @"1M");

        /* Formatting leaves no state behind. */
        EXPECT_STRING(en, 5, @"5");
        expect(@"multiplier untouched", en.multiplier ? @"set" : @"nil", @"nil");
        expect(@"format restored", en.positiveFormat, @"#,##0.###");
        expect(@"grouping restored", en.usesGroupingSeparator ? @"yes" : @"no", @"yes");

        /* Parsing. */
        EXPECT_NUMBER(en, @"5", @"5");
        EXPECT_NUMBER(en, @"12K", @"12000");
        EXPECT_NUMBER(en, @"1.5M", @"1500000");
        EXPECT_NUMBER(en, @"-2.5B", @"-2500000000");
        EXPECT_NUMBER(en, @"xyz", nil);

        /* A caller's own multiplier is respected. */
        DSShortNumberFormatter *hundred = formatter(@"en_US");
        hundred.multiplier = @100;
        EXPECT_STRING(hundred, 0.5, @"50");
        EXPECT_STRING(hundred, 150, @"15,000");
        EXPECT_STRING(hundred, 1234567, @"123.457M");
        EXPECT_STRING(hundred, 0.5, @"50");

        /* Fraction digits and rounding modes. */
        DSShortNumberFormatter *oneDigit = formatter(@"en_US");
        oneDigit.maximumFractionDigits = 1;
        oneDigit.minimumFractionDigits = 1;
        EXPECT_STRING(oneDigit, 1234567, @"1.2M");
        EXPECT_STRING(oneDigit, 5, @"5.0");
        EXPECT_STRING(oneDigit, 5.35, @"5.4");
        EXPECT_STRING(oneDigit, 999950, @"1.0M");
        expect(@"minimum fraction digits restored", @(oneDigit.minimumFractionDigits).stringValue, @"1");

        DSShortNumberFormatter *integer = formatter(@"en_US");
        integer.maximumFractionDigits = 0;
        EXPECT_STRING(integer, 999500, @"1M");
        EXPECT_STRING(integer, 999499, @"999K");
        EXPECT_STRING(integer, 1499, @"1K");

        DSShortNumberFormatter *roundsDown = formatter(@"en_US");
        roundsDown.maximumFractionDigits = 0;
        roundsDown.roundingMode = NSNumberFormatterRoundDown;
        EXPECT_STRING(roundsDown, 999999, @"999K");

        /* Locales, scripts and CLDR inheritance. */
        EXPECT_STRING(formatter(@"xx"), 1500, @"1.5K");
        EXPECT_STRING(formatter(@"af"), 1500, @"1,5 k");
        EXPECT_STRING(formatter(@"af"), 2500000, @"2,5 m");
        EXPECT_STRING(formatter(@"zh_CN"), 15000, @"1.5万");
        EXPECT_STRING(formatter(@"zh_Hant"), 15000, @"1.5萬");
        EXPECT_STRING(formatter(@"zh_Hant_TW"), 15000, @"1.5萬");
        EXPECT_STRING(formatter(@"zh_Hant_TW"), 1500, @"1,500");     /* bare "0" pattern: no compact form */
        EXPECT_STRING(formatter(@"sr_RS"), 15000, @"15 хиљ.");
        EXPECT_STRING(formatter(@"sr_Latn_RS"), 15000, @"15 hilj.");
        EXPECT_STRING(formatter(@"es_ES"), 2500, @"2,5 mil");
        EXPECT_STRING(formatter(@"es_ES"), 2500000000, @"2500 M");
        EXPECT_STRING(formatter(@"es_AR"), 2500, @"2,5 K");           /* es_419 overrides thousands only */
        EXPECT_STRING(formatter(@"es_AR"), 250000, @"250 k");
        EXPECT_STRING(formatter(@"es_AR"), 2500000000, @"2500 M");    /* ...and inherits the rest from es */
        EXPECT_STRING(formatter(@"th"), 1500, @"1.5K");
        EXPECT_STRING(formatter(@"th"), 2500000000, @"2.5B");
        EXPECT_STRING(formatter(@"pt_PT"), 2500, @"2,5 mil");
        EXPECT_STRING(formatter(@"pt_PT"), 2500000000, @"2,5 mM");
        EXPECT_STRING(formatter(@"pt_BR"), 2500000000, @"2,5 bi");
        EXPECT_STRING(formatter(@"cs_CZ"), 1500, @"1,5 tis.");
        EXPECT_STRING(formatter(@"cs_CZ"), 2500000, @"2,5 mil.");
        EXPECT_STRING(formatter(@"km"), 1500, @"1.5ពាន់");

        /* Other number styles. */
        DSShortNumberFormatter *currency = formatter(@"en_US");
        currency.numberStyle = NSNumberFormatterCurrencyStyle;
        EXPECT_STRING(currency, 1500, @"$1.50K");
        EXPECT_STRING(currency, -1500, @"-$1.50K");
        EXPECT_STRING(currency, 5, @"$5.00");

        DSShortNumberFormatter *percent = formatter(@"en_US");
        percent.numberStyle = NSNumberFormatterPercentStyle;
        EXPECT_STRING(percent, 15, @"1,500%");

        /* Edge values. */
        NSNumber *nilNumber = nil;
        expect(@"nil", [en stringFromNumber:nilNumber], nil);
        EXPECT_STRING(en, NAN, @"NaN");
        EXPECT_STRING(en, INFINITY, @"+∞");
        NSString *huge = [@"1" stringByAppendingString:[@"" stringByPaddingToLength:288 withString:@"0" startingAtIndex:0]];
        EXPECT_STRING(en, 1e300, [huge stringByAppendingString:@"T"]);

        /* Instances that come from an archive (or a nib) still load patterns. */
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:en requiringSecureCoding:NO error:NULL];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archive error:NULL];
        unarchiver.requiresSecureCoding = NO;
        DSShortNumberFormatter *decoded = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        EXPECT_STRING(decoded, 12000, @"12K");

        printf("%d failure%s\n", failures, failures == 1 ? "" : "s");
    }
    return failures ? 1 : 0;
}
