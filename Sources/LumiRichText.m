#import "LumiRichText.h"

static NSString *const kQuoteAttribute = @"LumiQuoteAttribute";

@implementation LumiRichTextRenderer

+ (NSArray<NSString *> *)imageURLsInText:(NSString *)text {
    if (!text.length) {
        return @[];
    }
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[photo\\]\\((https?://[^)\\s]+)\\)"
                                                                           options:0
                                                                             error:&error];
    if (!regex) {
        return @[];
    }
    NSMutableArray *urls = [NSMutableArray array];
    NSArray *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges > 1) {
            NSString *url = [text substringWithRange:[match rangeAtIndex:1]];
            [urls addObject:url];
        }
    }
    return urls;
}

+ (NSString *)stringByStrippingImageMarkers:(NSString *)text {
    if (!text.length) {
        return text ?: @"";
    }
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[photo\\]\\((?:https?|blob):[^)\\s]+\\)"
                                                                           options:0
                                                                             error:&error];
    if (!regex) {
        return text;
    }
    NSString *stripped = [regex stringByReplacingMatchesInString:text
                                                         options:0
                                                           range:NSMakeRange(0, text.length)
                                                    withTemplate:@""];
    return [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (UIColor *)quoteColorForTextColor:(UIColor *)textColor {
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0;
    if ([textColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return [UIColor colorWithRed:red green:green blue:blue alpha:alpha * 0.82];
    }
    return textColor;
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont {
    if (!text.length) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 2.5;
    style.paragraphSpacing = 2.0;

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = lines[index];
        BOOL isQuote = [line hasPrefix:@">"];
        NSString *content = line;
        if (isQuote) {
            content = [line substringFromIndex:1];
            if ([content hasPrefix:@" "]) {
                content = [content substringFromIndex:1];
            }
        }
        NSAttributedString *rendered = [self renderInlineText:content
                                                    textColor:(isQuote ? [self quoteColorForTextColor:textColor] : textColor)
                                                     baseFont:baseFont];
        NSMutableAttributedString *lineAttributed = [rendered mutableCopy];
        if (isQuote) {
            [lineAttributed addAttributes:@{
                kQuoteAttribute: @YES,
                NSBackgroundColorAttributeName: [UIColor colorWithWhite:0.5 alpha:0.14],
                NSForegroundColorAttributeName: [self quoteColorForTextColor:textColor],
            } range:NSMakeRange(0, lineAttributed.length)];
        }
        [lineAttributed addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, lineAttributed.length)];
        [result appendAttributedString:lineAttributed];
        if (index + 1 < lines.count) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                                                                           attributes:@{
                                                                               NSFontAttributeName: baseFont,
                                                                               NSForegroundColorAttributeName: textColor,
                                                                               NSParagraphStyleAttributeName: style,
                                                                           }]];
        }
    }
    return result;
}

+ (NSAttributedString *)renderInlineText:(NSString *)text
                               textColor:(UIColor *)textColor
                                baseFont:(UIFont *)baseFont {
    NSMutableAttributedString *output = [[NSMutableAttributedString alloc] initWithString:@""
                                                                              attributes:@{
        NSFontAttributeName: baseFont,
        NSForegroundColorAttributeName: textColor,
    }];

    NSError *error = nil;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"(\\*\\*|__)(.+?)\\1|(?<![\\*_])(\\*|_)([^\\*_\\n]+?)\\3|\\[photo\\]\\(https?://[^)\\s]+\\)"
                                                                             options:0
                                                                               error:&error];
    if (!pattern) {
        return [[NSAttributedString alloc] initWithString:text attributes:@{
            NSFontAttributeName: baseFont,
            NSForegroundColorAttributeName: textColor,
        }];
    }

    NSUInteger cursor = 0;
    NSArray *matches = [pattern matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches) {
        NSRange range = match.range;
        if (range.location > cursor) {
            NSAttributedString *plain = [self plainString:[text substringWithRange:NSMakeRange(cursor, range.location - cursor)]
                                                    font:baseFont
                                                   color:textColor];
            [output appendAttributedString:plain];
        }
        if (match.numberOfRanges > 2 && [match rangeAtIndex:2].location != NSNotFound) {
            NSString *bold = [text substringWithRange:[match rangeAtIndex:2]];
            UIFontDescriptor *descriptor = [baseFont.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
            UIFont *boldFont = descriptor ? [UIFont fontWithDescriptor:descriptor size:baseFont.pointSize] : [UIFont boldSystemFontOfSize:baseFont.pointSize];
            UIFont *displayFont = [UIFont fontWithName:@"Georgia-Bold" size:baseFont.pointSize] ?: boldFont;
            [output appendAttributedString:[[NSAttributedString alloc] initWithString:bold attributes:@{
                NSFontAttributeName: displayFont,
                NSForegroundColorAttributeName: textColor,
                NSKernAttributeName: @0.3,
            }]];
        } else if (match.numberOfRanges > 4 && [match rangeAtIndex:4].location != NSNotFound) {
            NSString *italic = [text substringWithRange:[match rangeAtIndex:4]];
            UIFontDescriptor *descriptor = [baseFont.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
            UIFont *italicFont = descriptor ? [UIFont fontWithDescriptor:descriptor size:baseFont.pointSize]
                                            : [UIFont italicSystemFontOfSize:baseFont.pointSize];
            [output appendAttributedString:[[NSAttributedString alloc] initWithString:italic attributes:@{
                NSFontAttributeName: italicFont,
                NSForegroundColorAttributeName: [textColor colorWithAlphaComponent:0.92],
            }]];
        } else {
            // Inline photo: keep it as a readable marker.
            [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"🖼 фото"
                                                                         attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:MAX(12.0, baseFont.pointSize - 1) weight:UIFontWeightMedium],
                NSForegroundColorAttributeName: textColor,
            }]];
        }
        cursor = range.location + range.length;
    }
    if (cursor < text.length) {
        NSAttributedString *plain = [self plainString:[text substringFromIndex:cursor]
                                                 font:baseFont
                                                color:textColor];
        [output appendAttributedString:plain];
    }
    return output;
}

+ (NSAttributedString *)plainString:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    return [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
    }];
}

@end
