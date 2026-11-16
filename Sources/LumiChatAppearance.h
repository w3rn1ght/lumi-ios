#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LumiChatAppearanceDidChangeNotification;

/// Persisted chat palette. Every colour is stored as a hex string in
/// `NSUserDefaults`, so a customised chat survives relaunches and app updates.
@interface LumiChatAppearance : NSObject

+ (instancetype)sharedAppearance;

/// Bold `**text**`, the quote outline and other accent details.
@property (nonatomic, strong) UIColor *boldColor;
/// Text inside a `> quote`.
@property (nonatomic, strong) UIColor *quoteTextColor;
/// Translucent fill behind a quote line.
@property (nonatomic, strong) UIColor *quoteFillColor;
@property (nonatomic, strong) UIColor *characterBubbleColor;
@property (nonatomic, strong) UIColor *characterTextColor;
@property (nonatomic, strong) UIColor *userBubbleColor;
@property (nonatomic, strong) UIColor *userTextColor;
@property (nonatomic, strong) UIColor *chatBackgroundColor;
@property (nonatomic, strong) UIColor *inputBarColor;

/// Name of the active preset, or "Своя палитра" after a manual change.
@property (nonatomic, copy, readonly) NSString *presetName;
@property (nonatomic, assign, readonly) BOOL isCustom;

+ (NSArray<NSString *> *)presetNames;
+ (nullable UIColor *)previewColorForPresetNamed:(NSString *)name;
/// Swatches offered by the manual colour picker.
+ (NSArray<UIColor *> *)paletteColors;
/// Human readable name for a palette key, used by the settings screen.
+ (NSString *)localizedNameForKey:(NSString *)key;
+ (NSArray<NSString *> *)allKeys;

- (void)applyPresetNamed:(NSString *)name;
/// Reverts every colour to the default green preset.
- (void)resetToDefault;

/// Keys: bold, quoteText, quoteFill, characterBubble, characterText,
/// userBubble, userText, background, inputBar.
- (nullable UIColor *)colorForKey:(NSString *)key;
- (NSString *)hexStringForKey:(NSString *)key;
- (void)setHexString:(NSString *)hex forKey:(NSString *)key;

+ (nullable UIColor *)colorFromHexString:(nullable NSString *)hex;
+ (NSString *)hexStringFromColor:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
