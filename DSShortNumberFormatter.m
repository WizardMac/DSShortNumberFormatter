
#import "DSShortNumberFormatter.h"

@implementation DSShortNumberFormatter

- (id)init {
    self = [super init];
    if (self) {
        NSURL *pattern_plist_url = [[NSBundle mainBundle] URLForResource:@"patterns" withExtension:@"plist"];
        pattern_dict = [[NSDictionary alloc] initWithContentsOfURL:pattern_plist_url];
    }
    return self;
}

- (void)dealloc {
    [pattern_dict release];
    [super dealloc];
}

- (NSArray *)patternsForLocale:(NSLocale *)locale {
    NSString *identifier = [locale localeIdentifier];
    if (pattern_dict[identifier])
        return pattern_dict[identifier];
    
    NSArray *components = [identifier componentsSeparatedByString:@"_"];
    if (pattern_dict[components[0]])
        return pattern_dict[components[0]];
    
    return pattern_dict[@"root"];
}

- (NSString *)stringFromNumber:(NSNumber *)number {
    double num_val = [number doubleValue];
    NSArray *patterns = [self patternsForLocale:[self locale]];
    double divide_zeroes = 0;
        
    for (NSDictionary *patternInfo in patterns) {
        NSString *pattern = patternInfo[@"pattern"];
        NSString *count = patternInfo[@"count"];
        NSString *type = patternInfo[@"type"];
        
        /* I don't think non-other patterns are different
         * for the short patterns. If this ever supports
         * the long pattern it will be necessary to
         * distinguish "one", "two", "few", and "many"
         */
        if (![count isEqualToString:@"other"])
            continue;
        
        if (num_val >= [type doubleValue]) {
            NSInteger type_zeroes = [type length] - 1;
            NSInteger pattern_zeroes = 0;
            for (int i=0; i<[pattern length]; i++) {
                if ([pattern characterAtIndex:i] == '0')
                    pattern_zeroes++;
            }
            divide_zeroes = (type_zeroes - pattern_zeroes + 1);
            
            [self setMultiplier:@(pow(10.0, -divide_zeroes))];
            [self setPositiveFormat:pattern];
            [self setNegativeFormat:pattern];
        }
    }
    
    return [super stringFromNumber:number];
}

@end
