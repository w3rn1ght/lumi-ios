#import <Foundation/Foundation.h>

/// Lumi's API is loosely typed: any field may be missing or explicitly `null`.
/// `NSNull` is not a string/number/array, and sending it a selector crashes the
/// app (`-[NSNull length]`, `-[NSNull compare:]`, `-[NSNull objectForKeyedSubscript:]`).
/// These helpers make payload parsing tolerant.

static inline NSDictionary *LumiAsDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : nil;
}

static inline NSArray *LumiAsArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? (NSArray *)value : nil;
}

static inline NSString *LumiAsString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static inline NSNumber *LumiAsNumber(id value) {
    return [value isKindOfClass:[NSNumber class]] ? (NSNumber *)value : nil;
}

/// Reads a value from a dictionary that may be any object (or `nil`).
static inline id LumiValue(id container, NSString *key) {
    NSDictionary *dictionary = LumiAsDictionary(container);
    if (!dictionary) {
        return nil;
    }
    return dictionary[key];
}

/// `dict[outer][inner]` without the risk of a nested subscript on `NSNull`.
static inline id LumiNestedValue(id container, NSString *outer, NSString *inner) {
    return LumiValue(LumiValue(container, outer), inner);
}

static inline NSString *LumiNestedString(id container, NSString *outer, NSString *inner) {
    return LumiAsString(LumiNestedValue(container, outer, inner));
}

/// Coerces numbers and strings into a display string.
static inline NSString *LumiStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return nil;
}

/// Safe comparison for date-like strings used in sort blocks.
static inline NSComparisonResult LumiCompareDates(id left, id right) {
    NSString *leftString = LumiStringValue(left) ?: @"";
    NSString *rightString = LumiStringValue(right) ?: @"";
    return [leftString compare:rightString];
}

/// The API sends ISO-8601 timestamps with anything from 0 to 6 fractional
/// digits (`2026-11-15T18:47:03.973641+00:00`). `NSISO8601DateFormatter` with
/// `WithFractionalSeconds` only reliably understands 3 digits, so every
/// microsecond timestamp used to fail to parse — which silently collapsed the
/// chat sort into an arbitrary order. This parser truncates the fraction to
/// milliseconds and also accepts Unix epochs in seconds or milliseconds.
static inline NSString *LumiDateStringByTrimmingFraction(NSString *string) {
    NSRange dot = [string rangeOfString:@"."];
    if (dot.location == NSNotFound) {
        return string;
    }
    NSUInteger digitsStart = dot.location + 1;
    NSUInteger digits = 0;
    while (digitsStart + digits < string.length && digits < 9) {
        unichar character = [string characterAtIndex:digitsStart + digits];
        if (character < '0' || character > '9') {
            break;
        }
        digits += 1;
    }
    if (digits <= 3) {
        return string;
    }
    return [[string substringToIndex:digitsStart + 3]
            stringByAppendingString:[string substringFromIndex:digitsStart + digits]];
}

static inline NSDate *LumiDateFromValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        double raw = [(NSNumber *)value doubleValue];
        if (raw > 100000000000.0) {
            raw /= 1000.0;
        }
        return raw > 0 ? [NSDate dateWithTimeIntervalSince1970:raw] : nil;
    }
    NSString *string = LumiAsString(value);
    if (!string.length) {
        return nil;
    }
    unichar first = [string characterAtIndex:0];
    if (first >= '0' && first <= '9' && [string rangeOfString:@"-"].location == NSNotFound) {
        double raw = [string doubleValue];
        if (raw > 100000000000.0) {
            raw /= 1000.0;
        }
        return raw > 0 ? [NSDate dateWithTimeIntervalSince1970:raw] : nil;
    }

    static NSArray<NSDateFormatter *> *formatters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *patterns = @[
            @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            @"yyyy-MM-dd'T'HH:mm:ssXXXXX",
            @"yyyy-MM-dd HH:mm:ss.SSSXXXXX",
            @"yyyy-MM-dd HH:mm:ssXXXXX",
            @"yyyy-MM-dd'T'HH:mm:ss.SSS",
            @"yyyy-MM-dd'T'HH:mm:ss",
            @"yyyy-MM-dd HH:mm:ss",
            @"yyyy-MM-dd",
        ];
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:patterns.count];
        for (NSString *pattern in patterns) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.dateFormat = pattern;
            [list addObject:formatter];
        }
        formatters = list;
    });

    NSString *trimmed = LumiDateStringByTrimmingFraction(string);
    @synchronized (formatters) {
        for (NSDateFormatter *formatter in formatters) {
            NSDate *date = [formatter dateFromString:trimmed];
            if (date) {
                return date;
            }
            if (![trimmed isEqualToString:string]) {
                date = [formatter dateFromString:string];
                if (date) {
                    return date;
                }
            }
        }
    }
    return nil;
}

