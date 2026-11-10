#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LumiWebAuthDidCompleteNotification;

/// Embedded browser used for OAuth (Google/Discord/Apple) and captcha-protected
/// email sign-in. Captures the `id.lumi.site` cookies once the user is signed in.
@interface LumiWebAuthViewController : UIViewController

- (instancetype)initWithPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
