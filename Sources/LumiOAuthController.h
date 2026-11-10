#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LumiOAuthProvider) {
    LumiOAuthProviderGoogle = 0,
    LumiOAuthProviderDiscord = 1,
    LumiOAuthProviderApple = 2,
};

/// Performs the same OAuth flow as the official Lumi app: opens the provider
/// through an authentication session, receives the `ai.lumi.app://auth-callback`
/// deep link and exchanges the one-time token for a cookie session.
@interface LumiOAuthController : NSObject

- (void)signInWithProvider:(LumiOAuthProvider)provider
                 presenter:(UIViewController *)presenter
                completion:(void (^)(BOOL ok, NSError * _Nullable error))completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
