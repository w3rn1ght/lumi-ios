#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Renders Lumi message text:
/// - `**bold**` / `__bold__` in a heavier font,
/// - `*italic*` / `_italic_` in an italic font,
/// - `> quote` with a rounded outlined block,
/// - inline `[photo](url)` image attachments, downloaded and shown inline.
@interface LumiRichTextRenderer : NSObject

+ (NSAttributedString *)attributedStringForText:(nullable NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont;

/// Like +attributedStringForText:, but lines that start with `prefixCommandName`
/// render the command name as a highlighted display-font prefix.
+ (NSAttributedString *)attributedStringForText:(nullable NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont
                             prefixCommandName:(nullable NSString *)prefixCommandName;

/// Chat palette aware variant: bold text and a leading `**Character Name**`
/// render in `boldColor`; `> quotes` use `quoteTextColor` on `quoteFillColor`.
+ (NSAttributedString *)attributedStringForText:(nullable NSString *)text
                                     textColor:(UIColor *)textColor
                                      baseFont:(UIFont *)baseFont
                                     boldColor:(nullable UIColor *)boldColor
                                 quoteTextColor:(nullable UIColor *)quoteTextColor
                                 quoteFillColor:(nullable UIColor *)quoteFillColor;

/// Image URLs referenced by `[photo](url)` markers.
+ (NSArray<NSString *> *)imageURLsInText:(nullable NSString *)text;

/// Removes `[photo](url)` markers so only the picture is shown in a bubble.
+ (NSString *)stringByStrippingImageMarkers:(nullable NSString *)text;

@end

NS_ASSUME_NONNULL_END
