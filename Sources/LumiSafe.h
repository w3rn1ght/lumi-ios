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

