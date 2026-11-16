#import "LumiRichText.h"

static NSString *const kQuoteAttribute = @"LumiQuoteAttribute";

static UIColor *LumiRichDefaultBoldColor(void) {
    return [UIColor colorWithRed:0.290 green:0.871 blue:0.502 alpha:1.0];
}

static UIColor *LumiRichDefaultQuoteTextColor(void) {
    return [UIColor colorWithRed:0.184 green:0.620 blue:0.369 alpha:1.0];
}

static UIColor *LumiRichDefaultQuoteFillColor(void) {
    return [UIColor colorWithRed:0.086 green:0.196 blue:0.122 alpha:1.0];
}

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

#pragma mark - Public API

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont {
    return [self attributedStringForText:text
                               textColor:textColor
                                baseFont:baseFont
                               boldColor:LumiRichDefaultBoldColor()
                           quoteTextColor:LumiRichDefaultQuoteTextColor()
                           quoteFillColor:LumiRichDefaultQuoteFillColor()];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont
                             prefixCommandName:(NSString *)prefixCommandName {
    // The legacy `prefixCommandName:@"**"` call meant "highlight a leading
    // bold character name". The dedicated renderer below does exactly that,
    // and also colours the name green instead of leaving raw asterisks.
    return [self attributedStringForText:text
                               textColor:textColor
                                baseFont:baseFont
                               boldColor:LumiRichDefaultBoldColor()
                           quoteTextColor:LumiRichDefaultQuoteTextColor()
                           quoteFillColor:LumiRichDefaultQuoteFillColor()];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont
                                     boldColor:(UIColor *)boldColor
                                 quoteTextColor:(UIColor *)quoteTextColor
                                 quoteFillColor:(UIColor *)quoteFillColor {
    if (!text.length) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    UIColor *accent = boldColor ?: LumiRichDefaultBoldColor();
    UIColor *quoteText = quoteTextColor ?: LumiRichDefaultQuoteTextColor();
    UIColor *quoteFill = quoteFillColor ?: LumiRichDefaultQuoteFillColor();
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

        NSMutableAttributedString *lineAttributed = [[NSMutableAttributedString alloc] init];
        NSRange leadingName = [self leadingBoldNameRangeInString:content];
        BOOL contentIsQuotePlaceholder = NO;
        if (!isQuote && leadingName.location == 0) {
            NSString *name = [content substringWithRange:leadingName];
            UIFont *displayFont = [self displayFontForBaseFont:baseFont];
            [lineAttributed appendAttributedString:[[NSAttributedString alloc] initWithString:name attributes:@{
                NSFontAttributeName: displayFont,
                NSForegroundColorAttributeName: accent,
                NSKernAttributeName: @0.3,
            }]];
            NSUInteger restStart = NSMaxRange(leadingName);
            if (restStart < content.length) {
                NSString *rest = [content substringFromIndex:restStart];
                if ([rest hasPrefix:@" "]) {
                    rest = [rest substringFromIndex:1];
                }
                if (rest.length) {
                    [lineAttributed appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{
                        NSFontAttributeName: baseFont,
                        NSForegroundColorAttributeName: textColor,
                    }]];
                    [lineAttributed appendAttributedString:[self renderInlineText:rest
                                                                      textColor:textColor
                                                                       baseFont:baseFont
                                                                      boldColor:accent]];
                }
            }
        } else {
            UIColor *lineColor = isQuote ? quoteText : textColor;
            lineAttributed = [[self renderInlineText:content
                                         textColor:lineColor
                                          baseFont:baseFont
                                         boldColor:(isQuote ? quoteText : accent)] mutableCopy];
        }

        if (isQuote) {
            [lineAttributed addAttributes:@{
                kQuoteAttribute: @YES,
                NSBackgroundColorAttributeName: quoteFill,
                NSForegroundColorAttributeName: quoteText,
            } range:NSMakeRange(0, lineAttributed.length)];
            if (!lineAttributed.length) {
                contentIsQuotePlaceholder = YES;
            }
        }
        [lineAttributed addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, lineAttributed.length)];
        if (contentIsQuotePlaceholder) {
            // A bare ">" still needs to render as a visible quote line.
            [lineAttributed appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{
                NSBackgroundColorAttributeName: quoteFill,
                NSFontAttributeName: baseFont,
                NSForegroundColorAttributeName: quoteText,
                NSParagraphStyleAttributeName: style,
            }]];
        }
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

#pragma mark - Inline

+ (UIFont *)displayFontForBaseFont:(UIFont *)baseFont {
    UIFontDescriptor *descriptor = [baseFont.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    UIFont *boldFont = descriptor ? [UIFont fontWithDescriptor:descriptor size:baseFont.pointSize]
                                  : [UIFont boldSystemFontOfSize:baseFont.pointSize];
    return [UIFont fontWithName:@"Georgia-Bold" size:baseFont.pointSize] ?: boldFont;
}

/// Returns the range of a `**Name**` prefix (without the asterisks) when the
/// string starts with one, otherwise a not-found range.
+ (NSRange)leadingBoldNameRangeInString:(NSString *)string {
    if (![string hasPrefix:@"**"]) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSRange close = [string rangeOfString:@"**" options:0 range:NSMakeRange(2, string.length - 2)];
    if (close.location == NSNotFound || close.location == 2) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange(2, close.location - 2);
}

+ (NSAttributedString *)renderInlineText:(NSString *)text
                               textColor:(UIColor *)textColor
                                baseFont:(UIFont *)baseFont
                               boldColor:(UIColor *)boldColor {
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
            [output appendAttributedString:[[NSAttributedString alloc] initWithString:bold attributes:@{
                NSFontAttributeName: [self displayFontForBaseFont:baseFont],
                NSForegroundColorAttributeName: boldColor ?: textColor,
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
