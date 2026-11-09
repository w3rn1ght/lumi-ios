#import <UIKit/UIKit.h>

static inline UIColor *LumiBackgroundColor(void) {
    return [UIColor colorWithRed:0.043 green:0.043 blue:0.071 alpha:1.0];
}

static inline UIColor *LumiSurfaceColor(void) {
    return [UIColor colorWithRed:0.094 green:0.094 blue:0.129 alpha:1.0];
}

static inline UIColor *LumiElevatedColor(void) {
    return [UIColor colorWithRed:0.129 green:0.129 blue:0.176 alpha:1.0];
}

static inline UIColor *LumiAccentColor(void) {
    return [UIColor colorWithRed:0.545 green:0.361 blue:0.965 alpha:1.0];
}

static inline UIColor *LumiTextColor(void) {
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}

static inline UIColor *LumiMutedColor(void) {
    return [UIColor colorWithWhite:0.58 alpha:1.0];
}

static inline UIFont *LumiFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

static inline UITextField *LumiTextField(NSString *placeholder) {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.backgroundColor = LumiSurfaceColor();
    field.textColor = LumiTextColor();
    field.tintColor = LumiAccentColor();
    field.font = LumiFont(16.0, UIFontWeightRegular);
    field.layer.cornerRadius = 12.0;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
                                                                 attributes:@{NSForegroundColorAttributeName: LumiMutedColor()}];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)];
    field.leftView = spacer;
    field.leftViewMode = UITextFieldViewModeAlways;
    [field.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return field;
}
