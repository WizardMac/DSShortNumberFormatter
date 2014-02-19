
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
    if ([self numberStyle] == NSNumberFormatterPercentStyle ||
        [self numberStyle] == NSNumberFormatterScientificStyle)
        return [super stringFromNumber:number];
    
    double num_val = [number doubleValue];
    NSArray *patterns = [self patternsForLocale:[self locale]];
    double divide_zeroes = 0;
    
    NSString *orig_positive_format = [self positiveFormat];
    NSString *orig_negative_format = [self negativeFormat];
        
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
        
        if (fabs(num_val) >= [type doubleValue]) {
            NSInteger type_zeroes = [type length] - 1;
            NSInteger pattern_zeroes = 0;
            NSInteger first_zero = -1;
            for (int i=0; i<[pattern length]; i++) {
                if ([pattern characterAtIndex:i] == '0') {
                    if (first_zero == -1)
                        first_zero = i;
                    pattern_zeroes++;
                }
            }
            divide_zeroes = (type_zeroes - pattern_zeroes + 1);
            
            [self setMultiplier:@(pow(10.0, -divide_zeroes))];
            
            NSString *new_positive_pattern = [pattern stringByReplacingCharactersInRange:NSMakeRange(first_zero, pattern_zeroes)
                                                                              withString:orig_positive_format];
            NSString *new_negative_pattern = [pattern stringByReplacingCharactersInRange:NSMakeRange(first_zero, pattern_zeroes)
                                                                              withString:orig_negative_format];
            
            [self setPositiveFormat:new_positive_pattern];
            [self setNegativeFormat:new_negative_pattern];
        }
    }
    
    NSString *result = [super stringFromNumber:number];
    [self setPositiveFormat:orig_positive_format];
    [self setNegativeFormat:orig_negative_format];
    return result;
}

@end
