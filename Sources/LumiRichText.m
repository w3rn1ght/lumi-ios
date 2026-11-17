#import "LumiRichText.h"
#import <objc/runtime.h>

static NSString *const kQuoteAttribute = @"LumiQuoteAttribute";
static const void *kLumiCircleCacheKey = &kLumiCircleCacheKey;

static UIColor *LumiRichDefaultBoldColor(void) {
    return [UIColor colorWithRed:0.290 green:0.871 blue:0.502 alpha:1.0];
}

static UIColor *LumiRichDefaultItalicColor(void) {
    return [UIColor colorWithRed:0.525 green:0.937 blue:0.675 alpha:1.0];
}

static UIColor *LumiRichDefaultQuoteTextColor(void) {
    return [UIColor colorWithRed:0.184 green:0.620 blue:0.369 alpha:1.0];
}

static UIColor *LumiRichDefaultQuoteFillColor(void) {
    return [UIColor colorWithRed:0.086 green:0.196 blue:0.122 alpha:1.0];
}

/// `Эрис Грейрат:`, `Эрис Грейрат —` and `Эрис Грейрат` all resolve to the same
/// portrait: strip punctuation that the model likes to append to names.
static NSString *LumiSpeakerLookupKey(NSString *name) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@":;,.!?—–-«»\"' \t"];
    while (trimmed.length && [trailing characterIsMember:[trimmed characterAtIndex:trimmed.length - 1]]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    return trimmed;
}

/// Cuts the image into a circle, aspect-filling it.
static UIImage *LumiCircularImage(UIImage *image, CGFloat side) {
    if (!image || side < 2.0) {
        return nil;
    }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0);
    CGRect rect = CGRectMake(0.0, 0.0, side, side);
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:rect];
    [circle addClip];

    CGSize imageSize = image.size;
    if (imageSize.width > 0.0 && imageSize.height > 0.0) {
        CGFloat ratio = MAX(CGRectGetWidth(rect) / imageSize.width, CGRectGetHeight(rect) / imageSize.height);
        CGSize drawSize = CGSizeMake(imageSize.width * ratio, imageSize.height * ratio);
        CGRect drawRect = CGRectMake((CGRectGetWidth(rect) - drawSize.width) / 2.0,
                                     (CGRectGetHeight(rect) - drawSize.height) / 2.0,
                                     drawSize.width,
                                     drawSize.height);
        [image drawInRect:drawRect];
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

/// Cropping portraits is done for every `**Name**` of every visible cell on
/// each redraw. Cache the rounded result on the source image so streaming does
/// not re-rasterise the same avatars dozens of times per second.
static UIImage *LumiCircularImageCached(UIImage *image, CGFloat side) {
    if (!image || side < 2.0) {
        return nil;
    }
    NSString *key = [NSString stringWithFormat:@"lumi.circle.%.0f", side];
    NSMutableDictionary *cache = objc_getAssociatedObject(image, kLumiCircleCacheKey);
    if (!cache) {
        cache = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(image, kLumiCircleCacheKey, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImage *cached = cache[key];
    if (cached) {
        return cached;
    }
    UIImage *circle = LumiCircularImage(image, side);
    if (circle) {
        cache[key] = circle;
    }
    return circle;
}

@interface LumiRichTextRenderer ()
+ (NSRange)leadingBoldNameRangeInString:(NSString *)string;
+ (UIFont *)displayFontForBaseFont:(UIFont *)baseFont;
+ (NSAttributedString *)avatarAttachmentForImage:(UIImage *)image font:(UIFont *)font;
+ (NSAttributedString *)renderInlineText:(NSString *)text
                               textColor:(UIColor *)textColor
                                baseFont:(UIFont *)baseFont
                               boldColor:(UIColor *)boldColor
                             italicColor:(UIColor *)italicColor
                            speakerImages:(NSDictionary<NSString *, UIImage *> *)speakerImages;
+ (NSAttributedString *)plainString:(NSString *)text font:(UIFont *)font color:(UIColor *)color;
@end

@implementation LumiRichTextRenderer

+ (NSArray<NSString *> *)imageURLsInText:(NSString *)text {
    if (!text.length || [text rangeOfString:@"photo]" options:NSCaseInsensitiveSearch].location == NSNotFound) {
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
    if ([text rangeOfString:@"photo]" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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

+ (NSArray<NSString *> *)boldNamesInText:(NSString *)text {
    if (!text.length
        || ([text rangeOfString:@"**"].location == NSNotFound
            && [text rangeOfString:@"__"].location == NSNotFound)) {
        return @[];
    }
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:\\*\\*|__)([^\\*_\\n]{1,60}?)(?:\\*\\*|__)"
                                                                           options:0
                                                                             error:&error];
    if (!regex) {
        return @[];
    }
    NSMutableArray *names = [NSMutableArray array];
    NSArray *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges < 2) {
            continue;
        }
        NSString *name = [[text substringWithRange:[match rangeAtIndex:1]]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        name = LumiSpeakerLookupKey(name);
        if (name.length) {
            [names addObject:name];
        }
    }
    return names;
}

#pragma mark - Public API

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont {
    return [self attributedStringForText:text
                               textColor:textColor
                                baseFont:baseFont
                               boldColor:LumiRichDefaultBoldColor()
                             italicColor:LumiRichDefaultItalicColor()
                           quoteTextColor:LumiRichDefaultQuoteTextColor()
                           quoteFillColor:LumiRichDefaultQuoteFillColor()
                            speakerImages:nil];
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
                             italicColor:LumiRichDefaultItalicColor()
                           quoteTextColor:LumiRichDefaultQuoteTextColor()
                           quoteFillColor:LumiRichDefaultQuoteFillColor()
                            speakerImages:nil];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont
                                     boldColor:(UIColor *)boldColor
                                 quoteTextColor:(UIColor *)quoteTextColor
                                 quoteFillColor:(UIColor *)quoteFillColor {
    return [self attributedStringForText:text
                               textColor:textColor
                                baseFont:baseFont
                               boldColor:boldColor
                             italicColor:LumiRichDefaultItalicColor()
                           quoteTextColor:quoteTextColor
                           quoteFillColor:quoteFillColor
                            speakerImages:nil];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont
                                     boldColor:(UIColor *)boldColor
                                   italicColor:(UIColor *)italicColor
                                 quoteTextColor:(UIColor *)quoteTextColor
                                 quoteFillColor:(UIColor *)quoteFillColor
                                  speakerImages:(NSDictionary<NSString *, UIImage *> *)speakerImages {
    if (!text.length) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    UIColor *accent = boldColor ?: LumiRichDefaultBoldColor();
    UIColor *italic = italicColor ?: LumiRichDefaultItalicColor();
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
            UIImage *image = speakerImages[LumiSpeakerLookupKey(name)];
            if (image) {
                NSAttributedString *attachment = [self avatarAttachmentForImage:image font:baseFont];
                if (attachment) {
                    [lineAttributed appendAttributedString:attachment];
                }
            }
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
                                                                       boldColor:accent
                                                                     italicColor:italic
                                                                    speakerImages:speakerImages]];
                }
            }
        } else {
            UIColor *lineColor = isQuote ? quoteText : textColor;
            lineAttributed = [[self renderInlineText:content
                                          textColor:lineColor
                                           baseFont:baseFont
                                          boldColor:(isQuote ? quoteText : accent)
                                        italicColor:(isQuote ? nil : italic)
                                       speakerImages:(isQuote ? nil : speakerImages)] mutableCopy];
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

+ (NSAttributedString *)avatarAttachmentForImage:(UIImage *)image font:(UIFont *)font {
    CGFloat side = round(MAX(16.0, font.pointSize * 1.25));
    UIImage *circle = LumiCircularImageCached(image, side);
    if (!circle) {
        return nil;
    }
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = circle;
    attachment.bounds = CGRectMake(0.0, round((font.capHeight - side) / 2.0), side, side);
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc]
        initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\u00A0" attributes:@{
        NSFontAttributeName: font,
    }]];
    return result;
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
                               boldColor:(UIColor *)boldColor
                             italicColor:(UIColor *)italicColor
                            speakerImages:(NSDictionary<NSString *, UIImage *> *)speakerImages {
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
            UIImage *image = speakerImages[LumiSpeakerLookupKey(bold)];
            if (image) {
                NSAttributedString *attachment = [self avatarAttachmentForImage:image font:baseFont];
                if (attachment) {
                    [output appendAttributedString:attachment];
                }
            }
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
                NSForegroundColorAttributeName: italicColor ?: [textColor colorWithAlphaComponent:0.92],
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
