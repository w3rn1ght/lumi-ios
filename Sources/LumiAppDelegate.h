#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LumiAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

- (void)showAuth;
- (void)showMain;

@end

NS_ASSUME_NONNULL_END
