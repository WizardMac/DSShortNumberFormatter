
#import <Foundation/Foundation.h>

@interface DSShortNumberFormatter : NSNumberFormatter {
    NSDictionary<NSString *, NSArray<NSDictionary<NSString *, NSString *> *> *> *pattern_dict;
}

@end
