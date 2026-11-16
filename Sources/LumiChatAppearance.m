#import "LumiChatAppearance.h"
#import <math.h>

NSString *const LumiChatAppearanceDidChangeNotification = @"LumiChatAppearanceDidChangeNotification";

static NSString *const kLumiAppearanceColorsKey = @"LumiChatAppearanceColors";
static NSString *const kLumiAppearancePresetKey = @"LumiChatAppearancePreset";
static NSString *const kLumiAppearanceCustomKey = @"LumiChatAppearanceCustom";
static NSString *const kLumiDefaultPreset = @"Изумруд";

static UIColor *LumiColor(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *LumiStringValueInDictionary(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

@interface LumiChatAppearance ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIColor *> *colors;
@property (nonatomic, copy, readwrite) NSString *presetName;
@property (nonatomic, assign, readwrite) BOOL isCustom;
@property (nonatomic, assign) BOOL applyingPreset;
@end

@implementation LumiChatAppearance

+ (instancetype)sharedAppearance {
    static LumiChatAppearance *appearance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        appearance = [[LumiChatAppearance alloc] init];
    });
    return appearance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _colors = [NSMutableDictionary dictionary];
        _presetName = kLumiDefaultPreset;
        _isCustom = NO;
        [self loadStoredColors];
    }
    return self;
}

#pragma mark - Presets

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)presets {
    static NSDictionary *presets;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presets = @{
            @"Изумруд": @{
                @"bold": @"#4ADE80",
                @"quoteText": @"#2F9E5E",
                @"quoteFill": @"#16321F",
                @"characterBubble": @"#151D18",
                @"characterText": @"#ECF7EF",
                @"userBubble": @"#1F7A4D",
                @"userText": @"#FFFFFF",
                @"background": @"#080C09",
                @"inputBar": @"#101712",
            },
            @"Аметист": @{
                @"bold": @"#A78BFA",
                @"quoteText": @"#8B5CF6",
                @"quoteFill": @"#241B3A",
                @"characterBubble": @"#181821",
                @"characterText": @"#F4F4FA",
                @"userBubble": @"#8B5CF6",
                @"userText": @"#FFFFFF",
                @"background": @"#0B0B12",
                @"inputBar": @"#181821",
            },
            @"Океан": @{
                @"bold": @"#38BDF8",
                @"quoteText": @"#0EA5E9",
                @"quoteFill": @"#0F2A3B",
                @"characterBubble": @"#10222E",
                @"characterText": @"#E8F5FB",
                @"userBubble": @"#0369A1",
                @"userText": @"#FFFFFF",
                @"background": @"#06101A",
                @"inputBar": @"#0B1A25",
            },
            @"Закат": @{
                @"bold": @"#FDBA74",
                @"quoteText": @"#F97316",
                @"quoteFill": @"#3A1E10",
                @"characterBubble": @"#221512",
                @"characterText": @"#FDF1E8",
                @"userBubble": @"#C2410C",
                @"userText": @"#FFFFFF",
                @"background": @"#120A08",
                @"inputBar": @"#1C100C",
            },
            @"Роза": @{
                @"bold": @"#F9A8D4",
                @"quoteText": @"#DB2777",
                @"quoteFill": @"#3A1029",
                @"characterBubble": @"#24131C",
                @"characterText": @"#FDEBF3",
                @"userBubble": @"#BE185D",
                @"userText": @"#FFFFFF",
                @"background": @"#120A0F",
                @"inputBar": @"#1B0D14",
            },
            @"Графит": @{
                @"bold": @"#E5E7EB",
                @"quoteText": @"#9CA3AF",
                @"quoteFill": @"#242427",
                @"characterBubble": @"#1A1A1D",
                @"characterText": @"#F3F3F4",
                @"userBubble": @"#4B4B55",
                @"userText": @"#FFFFFF",
                @"background": @"#0B0B0C",
                @"inputBar": @"#151517",
            },
        };
    });
    return presets;
}

+ (NSArray<NSString *> *)presetNames {
    return @[@"Изумруд", @"Аметист", @"Океан", @"Закат", @"Роза", @"Графит"];
}

+ (UIColor *)previewColorForPresetNamed:(NSString *)name {
    NSDictionary *preset = [self presets][name];
    if (!preset) {
        return nil;
    }
    return [self colorFromHexString:preset[@"bold"]];
}

#pragma mark - Palette

+ (NSArray<UIColor *> *)paletteColors {
    static NSArray<UIColor *> *colors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colors = @[
            LumiColor(0x4ADE80), LumiColor(0x22C55E), LumiColor(0x16A34A), LumiColor(0x2F9E5E),
            LumiColor(0x84CC16), LumiColor(0x14B8A6), LumiColor(0x06B6D4), LumiColor(0x38BDF8),
            LumiColor(0x0EA5E9), LumiColor(0x3B82F6), LumiColor(0x6366F1), LumiColor(0x8B5CF6),
            LumiColor(0xA855F7), LumiColor(0xD946EF), LumiColor(0xEC4899), LumiColor(0xF43F5E),
            LumiColor(0xEF4444), LumiColor(0xF97316), LumiColor(0xFB923C), LumiColor(0xFACC15),
            LumiColor(0xEAB308), LumiColor(0xA3A3A3), LumiColor(0xE5E7EB), LumiColor(0xFFFFFF),
        ];
    });
    return colors;
}

#pragma mark - Keys

+ (NSArray<NSString *> *)allKeys {
    return @[@"bold", @"quoteText", @"quoteFill", @"characterBubble", @"characterText",
             @"userBubble", @"userText", @"background", @"inputBar"];
}

/// Human readable names used by the appearance screen.
+ (NSString *)localizedNameForKey:(NSString *)key {
    if ([key isEqualToString:@"bold"]) return @"Жирный текст / акцент";
    if ([key isEqualToString:@"quoteText"]) return @"Текст цитаты";
    if ([key isEqualToString:@"quoteFill"]) return @"Обводка цитаты";
    if ([key isEqualToString:@"characterBubble"]) return @"Пузырь персонажа";
    if ([key isEqualToString:@"characterText"]) return @"Текст персонажа";
    if ([key isEqualToString:@"userBubble"]) return @"Пузырь пользователя";
    if ([key isEqualToString:@"userText"]) return @"Текст пользователя";
    if ([key isEqualToString:@"background"]) return @"Фон чата";
    if ([key isEqualToString:@"inputBar"]) return @"Панель ввода";
    return key;
}

#pragma mark - Storage

- (void)loadStoredColors {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storedPreset = [defaults stringForKey:kLumiAppearancePresetKey];
    if (!storedPreset.length) {
        storedPreset = kLumiDefaultPreset;
    }
    NSDictionary *preset = [[self class] presets][storedPreset];
    if (!preset) {
        storedPreset = kLumiDefaultPreset;
        preset = [[self class] presets][storedPreset];
    }
    _presetName = [storedPreset copy];
    _isCustom = [defaults boolForKey:kLumiAppearanceCustomKey];

    NSDictionary *stored = [defaults dictionaryForKey:kLumiAppearanceColorsKey];
    for (NSString *key in [[self class] allKeys]) {
        NSString *hex = LumiStringValueInDictionary(stored, key) ?: preset[key];
        UIColor *color = [[self class] colorFromHexString:hex];
        if (color) {
            self.colors[key] = color;
        }
    }
}

- (void)save {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *colors = [NSMutableDictionary dictionary];
    for (NSString *key in [[self class] allKeys]) {
        colors[key] = [self hexStringForKey:key];
    }
    [defaults setObject:colors forKey:kLumiAppearanceColorsKey];
    [defaults setObject:self.presetName ?: kLumiDefaultPreset forKey:kLumiAppearancePresetKey];
    [defaults setBool:self.isCustom forKey:kLumiAppearanceCustomKey];
}

- (NSString *)hexStringForKey:(NSString *)key {
    UIColor *color = self.colors[key];
    return color ? [[self class] hexStringFromColor:color] : @"";
}

- (void)setHexString:(NSString *)hex forKey:(NSString *)key {
    UIColor *color = [[self class] colorFromHexString:hex];
    if (!color) {
        return;
    }
    [self storeColor:color key:key];
}

- (void)storeColor:(UIColor *)color key:(NSString *)key {
    if (!color || !key.length) {
        return;
    }
    self.colors[key] = color;
    if (self.applyingPreset) {
        return;
    }
    self.presetName = @"Своя палитра";
    self.isCustom = YES;
    [self save];
    [self notifyChange];
}

#pragma mark - Properties

- (UIColor *)boldColor { return self.colors[@"bold"]; }
- (void)setBoldColor:(UIColor *)color { [self storeColor:color key:@"bold"]; }
- (UIColor *)quoteTextColor { return self.colors[@"quoteText"]; }
- (void)setQuoteTextColor:(UIColor *)color { [self storeColor:color key:@"quoteText"]; }
- (UIColor *)quoteFillColor { return self.colors[@"quoteFill"]; }
- (void)setQuoteFillColor:(UIColor *)color { [self storeColor:color key:@"quoteFill"]; }
- (UIColor *)characterBubbleColor { return self.colors[@"characterBubble"]; }
- (void)setCharacterBubbleColor:(UIColor *)color { [self storeColor:color key:@"characterBubble"]; }
- (UIColor *)characterTextColor { return self.colors[@"characterText"]; }
- (void)setCharacterTextColor:(UIColor *)color { [self storeColor:color key:@"characterText"]; }
- (UIColor *)userBubbleColor { return self.colors[@"userBubble"]; }
- (void)setUserBubbleColor:(UIColor *)color { [self storeColor:color key:@"userBubble"]; }
- (UIColor *)userTextColor { return self.colors[@"userText"]; }
- (void)setUserTextColor:(UIColor *)color { [self storeColor:color key:@"userText"]; }
- (UIColor *)chatBackgroundColor { return self.colors[@"background"]; }
- (void)setChatBackgroundColor:(UIColor *)color { [self storeColor:color key:@"background"]; }
- (UIColor *)inputBarColor { return self.colors[@"inputBar"]; }
- (void)setInputBarColor:(UIColor *)color { [self storeColor:color key:@"inputBar"]; }

#pragma mark - Mutations

- (void)applyPresetNamed:(NSString *)name {
    NSDictionary *preset = [[self class] presets][name];
    if (!preset) {
        return;
    }
    self.applyingPreset = YES;
    for (NSString *key in [[self class] allKeys]) {
        UIColor *color = [[self class] colorFromHexString:preset[key]];
        if (color) {
            self.colors[key] = color;
        }
    }
    self.applyingPreset = NO;
    self.presetName = [name copy];
    self.isCustom = NO;
    [self save];
    [self notifyChange];
}

- (void)resetToDefault {
    [self applyPresetNamed:kLumiDefaultPreset];
}

- (void)notifyChange {
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:LumiChatAppearanceDidChangeNotification object:self];
    };
    if ([NSThread isMainThread]) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

#pragma mark - Hex

+ (UIColor *)colorFromHexString:(NSString *)hex {
    NSString *value = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value hasPrefix:@"#"]) {
        value = [value substringFromIndex:1];
    }
    if (value.length != 6 && value.length != 8) {
        return nil;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned long long raw = 0;
    if (![scanner scanHexLongLong:&raw]) {
        return nil;
    }
    if (value.length == 6) {
        return [UIColor colorWithRed:((raw >> 16) & 0xFF) / 255.0
                               green:((raw >> 8) & 0xFF) / 255.0
                                blue:(raw & 0xFF) / 255.0
                               alpha:1.0];
    }
    return [UIColor colorWithRed:((raw >> 24) & 0xFF) / 255.0
                           green:((raw >> 16) & 0xFF) / 255.0
                            blue:((raw >> 8) & 0xFF) / 255.0
                           alpha:(raw & 0xFF) / 255.0];
}

+ (NSString *)hexStringFromColor:(UIColor *)color {
    CGFloat red = 0, green = 0, blue = 0, alpha = 1;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return @"#FFFFFF";
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned int)lround(red * 255.0),
            (unsigned int)lround(green * 255.0),
            (unsigned int)lround(blue * 255.0)];
}

@end
