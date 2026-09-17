
#import "DSShortNumberFormatter.h"

typedef NSDictionary<NSString *, NSString *> DSPatternInfo;

/* Countries whose Spanish inherits from es_419 in CLDR's parentLocales. */
static NSSet<NSString *> *DSLatinAmericanSpanishCountries(void) {
    static NSSet *countries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        countries = [[NSSet alloc] initWithArray:@[@"AR", @"BO", @"BR", @"BZ", @"CL", @"CO", @"CR", @"CU",
                                                   @"DO", @"EC", @"GT", @"HN", @"MX", @"NI", @"PA", @"PE",
                                                   @"PR", @"PY", @"SV", @"US", @"UY", @"VE"]];
    });
    return countries;
}

@implementation DSShortNumberFormatter

#pragma mark - Pattern data

/* Loaded once per process, and lazily, so instances created with
 * -initWithCoder: (nibs, archives) work the same as -init. */
+ (NSDictionary<NSString *, NSArray<DSPatternInfo *> *> *)patternDictionary {
    static NSDictionary *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSBundle bundleForClass:self] URLForResource:@"patterns" withExtension:@"plist"];
        if (!url)
            url = [NSBundle.mainBundle URLForResource:@"patterns" withExtension:@"plist"];
        if (url)
            patterns = [[NSDictionary alloc] initWithContentsOfURL:url];
        if (!patterns) {
            NSLog(@"DSShortNumberFormatter: patterns.plist not found; numbers will not be abbreviated");
            patterns = [[NSDictionary alloc] init];
        }
    });
    return patterns;
}

+ (NSArray<NSString *> *)lookupKeysForLocale:(NSLocale *)locale {
    NSString *language = locale.languageCode;
    NSString *script = locale.scriptCode;
    NSString *country = locale.countryCode;
    if (!language.length)
        return @[@"root"];

    /* NSLocale drops the script from zh_Hant_TW, so restore CLDR's likely subtag. */
    if (!script && [language isEqualToString:@"zh"] &&
        ([country isEqualToString:@"TW"] || [country isEqualToString:@"HK"] || [country isEqualToString:@"MO"]))
        script = @"Hant";

    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    if (script && country)
        [keys addObject:[NSString stringWithFormat:@"%@_%@_%@", language, script, country]];
    if (script)
        [keys addObject:[NSString stringWithFormat:@"%@_%@", language, script]];
    if (country)
        [keys addObject:[NSString stringWithFormat:@"%@_%@", language, country]];
    if ([language isEqualToString:@"es"] && [DSLatinAmericanSpanishCountries() containsObject:country])
        [keys addObject:@"es_419"];
    [keys addObject:language];
    [keys addObject:@"root"];
    return keys;
}

/* The "other" plural patterns for the locale, sorted by ascending magnitude.
 * CLDR inherits per item, not per file: es_419 overrides only the thousands
 * pattern and takes the rest from es, so each magnitude is resolved separately
 * along the fallback chain. */
- (NSArray<DSPatternInfo *> *)patternsForLocale:(NSLocale *)locale {
    NSDictionary *dict = [self.class patternDictionary];
    NSMutableDictionary<NSString *, DSPatternInfo *> *byType = [NSMutableDictionary dictionary];
    for (NSString *key in [self.class lookupKeysForLocale:locale]) {
        for (DSPatternInfo *info in dict[key]) {
            NSString *type = info[@"type"];
            if ([info[@"count"] isEqualToString:@"other"] && type && !byType[type])
                byType[type] = info;
        }
    }
    if (!byType.count)
        return nil;
    return [byType.allValues sortedArrayUsingComparator:^NSComparisonResult(DSPatternInfo *a, DSPatternInfo *b) {
        double ta = a[@"type"].doubleValue, tb = b[@"type"].doubleValue;
        return ta < tb ? NSOrderedAscending : ta > tb ? NSOrderedDescending : NSOrderedSame;
    }];
}

#pragma mark - Pattern arithmetic

/* Range of the run of zeroes in a CLDR compact pattern such as "00K". */
static NSRange DSZeroRange(NSString *pattern) {
    return [pattern rangeOfString:@"0+" options:NSRegularExpressionSearch];
}

/* CLDR uses a bare "0" to mean "no compact form at this magnitude". */
static BOOL DSPatternIsUsable(DSPatternInfo *info) {
    NSString *pattern = info[@"pattern"];
    return DSZeroRange(pattern).location != NSNotFound && ![pattern isEqualToString:@"0"];
}

/* Power of ten by which the value is scaled before being shown with the pattern:
 * a value of 1500 with type "1000" and pattern "0K" is shown as 1.5, so -3. */
static short DSScaleExponent(DSPatternInfo *info) {
    NSString *type = info[@"type"];
    NSRange zeroes = DSZeroRange(info[@"pattern"]);
    return (short)((NSInteger)zeroes.length - (NSInteger)type.length);
}

- (BOOL)usesCompactPatterns {
    return self.numberStyle != NSNumberFormatterPercentStyle &&
           self.numberStyle != NSNumberFormatterScientificStyle;
}

- (NSDecimalNumberHandler *)roundingBehavior {
    NSRoundingMode mode;
    switch (self.roundingMode) {
        case NSNumberFormatterRoundCeiling:
        case NSNumberFormatterRoundUp:       mode = NSRoundUp; break;
        case NSNumberFormatterRoundFloor:
        case NSNumberFormatterRoundDown:     mode = NSRoundDown; break;
        case NSNumberFormatterRoundHalfEven: mode = NSRoundBankers; break;
        default:                             mode = NSRoundPlain; break;
    }
    return [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:mode
                                                                  scale:(short)self.maximumFractionDigits
                                                       raiseOnExactness:NO
                                                        raiseOnOverflow:NO
                                                       raiseOnUnderflow:NO
                                                    raiseOnDivideByZero:NO];
}

/* Picks the pattern for `number`, taking into account that rounding to the
 * formatter's fraction digits may carry the value into the next magnitude
 * (999,950 with one fraction digit is "1M", not "1,000K"). Returns nil when
 * the number should be formatted normally. */
- (DSPatternInfo *)patternForNumber:(NSNumber *)number
                          patterns:(NSArray<DSPatternInfo *> *)patterns
                      scaledValue:(NSNumber **)scaledValue {
    double value = fabs(number.doubleValue);
    NSInteger index = -1;
    for (NSInteger i = 0; i < patterns.count; i++) {
        if (value >= patterns[i][@"type"].doubleValue)
            index = i;
        else
            break;
    }
    if (index < 0)
        return nil;

    /* NSDecimal holds 38 digits with exponents up to 127; beyond that, fall back to
     * double arithmetic, where the rounding error no longer matters. */
    NSDecimalNumber *decimal = nil;
    if (value < 1e120) {
        decimal = [NSDecimalNumber decimalNumberWithDecimal:number.decimalValue];
        if ([decimal isEqualToNumber:NSDecimalNumber.notANumber])
            decimal = nil;
    }

    NSDecimalNumberHandler *rounding = [self roundingBehavior];
    while (YES) {
        DSPatternInfo *info = patterns[index];
        if (!DSPatternIsUsable(info))
            return nil;

        short exponent = DSScaleExponent(info);
        NSNumber *scaled;
        BOOL carries = NO;
        if (decimal) {
            scaled = [decimal decimalNumberByMultiplyingByPowerOf10:exponent];
            if (index + 1 < patterns.count) {
                NSDecimalNumber *rounded = [(NSDecimalNumber *)scaled decimalNumberByRoundingAccordingToBehavior:rounding];
                double shown = fabs([rounded decimalNumberByMultiplyingByPowerOf10:-exponent].doubleValue);
                carries = shown >= patterns[index + 1][@"type"].doubleValue;
            }
        } else {
            scaled = @(number.doubleValue * pow(10, exponent));
        }
        if (!carries) {
            *scaledValue = scaled;
            return info;
        }
        index++;
    }
}

#pragma mark - Formatting

- (NSString *)stringFromNumber:(NSNumber *)number {
    if (!number || ![self usesCompactPatterns] || !isfinite(number.doubleValue))
        return [super stringFromNumber:number];

    NSArray<DSPatternInfo *> *patterns = [self patternsForLocale:self.locale];
    NSNumber *scaled = nil;
    DSPatternInfo *info = [self patternForNumber:number patterns:patterns scaledValue:&scaled];
    if (!info)
        return [super stringFromNumber:number];

    NSString *orig_positive_format = self.positiveFormat;
    NSString *orig_negative_format = self.negativeFormat;
    NSString *orig_negative_prefix = self.negativePrefix;
    BOOL orig_uses_grouping = self.usesGroupingSeparator;

    [self applyPattern:info[@"pattern"] positiveFormat:orig_positive_format
        negativeFormat:orig_negative_format negativePrefix:orig_negative_prefix];
    /* Compact numbers never group digits: CLDR's "0000 M" is "2500 M", not "2,500 M". */
    self.usesGroupingSeparator = NO;
    NSString *result = [super stringFromNumber:scaled];

    self.usesGroupingSeparator = orig_uses_grouping;
    self.positiveFormat = orig_positive_format;
    self.negativeFormat = orig_negative_format;
    self.negativePrefix = orig_negative_prefix;
    return result;
}

- (NSNumber *)numberFromString:(NSString *)string {
    NSNumber *result = [super numberFromString:string];
    if (result || ![self usesCompactPatterns])
        return result;

    NSString *orig_positive_format = self.positiveFormat;
    NSString *orig_negative_format = self.negativeFormat;
    NSString *orig_negative_prefix = self.negativePrefix;

    for (DSPatternInfo *info in [self patternsForLocale:self.locale]) {
        if (!DSPatternIsUsable(info))
            continue;
        [self applyPattern:info[@"pattern"] positiveFormat:orig_positive_format
            negativeFormat:orig_negative_format negativePrefix:orig_negative_prefix];
        NSNumber *parsed = [super numberFromString:string];
        if (parsed) {
            NSDecimalNumber *decimal = [NSDecimalNumber decimalNumberWithDecimal:parsed.decimalValue];
            result = [decimal decimalNumberByMultiplyingByPowerOf10:-DSScaleExponent(info)];
            break;
        }
    }

    self.positiveFormat = orig_positive_format;
    self.negativeFormat = orig_negative_format;
    self.negativePrefix = orig_negative_prefix;
    return result;
}

/* Splices the caller's number formats into the zeroes of a CLDR pattern,
 * so "0K" with "#,##0.###" becomes "#,##0.###K". */
- (void)applyPattern:(NSString *)pattern
      positiveFormat:(NSString *)positiveFormat
      negativeFormat:(NSString *)negativeFormat
      negativePrefix:(NSString *)negativePrefix {
    NSRange zeroes = DSZeroRange(pattern);
    self.positiveFormat = [pattern stringByReplacingCharactersInRange:zeroes withString:positiveFormat];
    self.negativeFormat = [pattern stringByReplacingCharactersInRange:zeroes withString:negativeFormat];
    /* Setting negativeFormat discards the prefix, so put it back. */
    self.negativePrefix = negativePrefix;
}

@end
