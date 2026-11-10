#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const LumiGoogleAuthErrorDomain;

typedef NS_ENUM(NSInteger, LumiGoogleAuthErrorCode) {
    LumiGoogleAuthErrorCancelled = 1,
    LumiGoogleAuthErrorFailed = 2,
};

typedef void (^LumiGoogleAuthCompletion)(NSString * _Nullable idToken,
                                         NSString * _Nullable email,
                                         NSError * _Nullable error);

/// Runs Google's OAuth 2.0 code flow with PKCE and returns an OpenID Connect
/// ID token whose audience is Lumi's web client ID, matching the official app.
@interface LumiGoogleAuth : NSObject

+ (instancetype)sharedAuth;

- (void)signInFromViewController:(UIViewController *)presenter
                      completion:(LumiGoogleAuthCompletion)completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
