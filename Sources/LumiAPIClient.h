#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LumiAPICompletion)(id _Nullable result, NSError * _Nullable error);
typedef void (^LumiAPIRawCompletion)(NSDictionary * _Nullable json, NSError * _Nullable error);

extern NSString *const LumiAPIErrorDomain;

@interface LumiAPIClient : NSObject

+ (instancetype)sharedClient;

@property (nonatomic, copy, readonly, nullable) NSString *accessToken;
@property (nonatomic, copy, readonly, nullable) NSString *refreshToken;
@property (nonatomic, copy, readonly, nullable) NSString *userEmail;

- (BOOL)isAuthenticated;
- (void)logout;

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(LumiAPICompletion)completion;

- (void)registerWithEmail:(NSString *)email
                 password:(NSString *)password
               completion:(LumiAPICompletion)completion;

- (void)refreshIfNeededWithCompletion:(void (^)(BOOL ok))completion;

- (void)fetchProfileWithCompletion:(LumiAPIRawCompletion)completion;
- (void)fetchSessionsWithCompletion:(LumiAPIRawCompletion)completion;
- (void)fetchMessagesForSession:(NSString *)sessionID
                     completion:(LumiAPIRawCompletion)completion;
- (void)createSessionWithDeviceContext:(NSDictionary *)deviceContext
                            completion:(LumiAPIRawCompletion)completion;

/// Sends a chat message. Returns the decoded JSON response.
- (void)sendMessage:(NSString *)text
          sessionID:(NSString *)sessionID
             turnID:(nullable NSString *)turnID
             stepID:(nullable NSString *)stepID
         completion:(LumiAPIRawCompletion)completion;

/// Public Lumi web API (no auth required).
- (void)fetchCatalogWithCompletion:(LumiAPIRawCompletion)completion;
- (void)fetchCharacterWithID:(NSString *)characterID
                  completion:(LumiAPIRawCompletion)completion;

/// Password reset through the public web auth service (no captcha required).
- (void)requestPasswordResetForEmail:(NSString *)email
                          completion:(void (^)(BOOL ok, NSString *message))completion;

@end

NS_ASSUME_NONNULL_END
