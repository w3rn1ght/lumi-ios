#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LumiAPICompletion)(id _Nullable result, NSError * _Nullable error);

extern NSString *const LumiAPIErrorDomain;
extern NSString *const LumiAPIDidUnauthorizedNotification;
extern NSString *const LumiAuthDidChangeNotification;

/// NSUserDefaults-backed session marker (works for rootful jailbreak apps).
@interface LumiSecureStore : NSObject
+ (void)setObject:(nullable id)object forKey:(NSString *)key;
+ (nullable id)objectForKey:(NSString *)key;
+ (BOOL)hasSessionMaterial;
+ (void)markSessionActive:(BOOL)active;
+ (void)clearSession;
@end

@interface LumiSessionUser : NSObject
@property (nonatomic, copy) NSString *userID;
@property (nonatomic, copy, nullable) NSString *email;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *avatarURL;
+ (instancetype)userFromJSON:(NSDictionary *)json;
- (NSString *)displayName;
@end

@class LumiChatStream;

@interface LumiAPI : NSObject

+ (instancetype)sharedClient;

@property (nonatomic, strong, readonly, nullable) LumiSessionUser *currentUser;
/// YES when a session marker, bearer token or session cookie is present.
@property (nonatomic, assign, readonly) BOOL isAuthenticated;

- (void)refreshSessionWithCompletion:(void (^)(BOOL ok))completion;

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(LumiAPICompletion)completion;

/// Exchanges the one-time deep-link token from the OAuth flow for a session.
- (void)exchangeAppToken:(NSString *)token completion:(void (^)(NSError * _Nullable error))completion;

- (void)logout;

/// Persists cookies captured from another component (e.g. WKWebView).
- (void)storeCookies:(NSArray<NSHTTPCookie *> *)cookies;
- (NSArray<NSHTTPCookie *> *)lumiCookies;

#pragma mark - Catalog

- (void)fetchCharacterIDsWithCompletion:(LumiAPICompletion)completion;
- (void)fetchCharacterWithID:(NSString *)characterID completion:(LumiAPICompletion)completion;
- (void)fetchStoryIDsWithCompletion:(LumiAPICompletion)completion;
- (void)fetchStoryWithID:(NSString *)storyID completion:(LumiAPICompletion)completion;
- (void)fetchTagsWithCompletion:(LumiAPICompletion)completion;

#pragma mark - Chats

- (void)fetchChatsWithCompletion:(LumiAPICompletion)completion;
- (void)fetchChatWithID:(NSString *)chatID completion:(LumiAPICompletion)completion;
- (void)openChatWithCharacterID:(nullable NSString *)characterID
                        storyID:(nullable NSString *)storyID
                     completion:(LumiAPICompletion)completion;
- (void)fetchMessagesForChatID:(NSString *)chatID
                         limit:(NSInteger)limit
                        before:(nullable NSString *)before
                    completion:(LumiAPICompletion)completion;
- (void)markChatRead:(NSString *)chatID;
- (void)seedIntroForChat:(NSString *)chatID completion:(nullable LumiAPICompletion)completion;
- (void)deleteChat:(NSString *)chatID completion:(nullable LumiAPICompletion)completion;

/// Opens the SSE stream for POST /chats/{id}/messages.
- (LumiChatStream *)sendMessage:(NSString *)content
                         chatID:(NSString *)chatID
                   eventHandler:(void (^)(NSString *type, NSDictionary *payload))eventHandler
                     completion:(void (^)(NSError * _Nullable error))completion;

@end

#pragma mark - SSE helper

@interface LumiChatStream : NSObject
- (void)start;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
