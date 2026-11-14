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

/// Cursor-paged catalog endpoints returning full card data (name, cover, tags, message_count, etc.).
/// Endpoint: GET /characters?scope=all&fields=card&limit=100&sort=popular&cursor=...
- (void)fetchCharacterCardsWithCursor:(nullable NSString *)cursor
                         completion:(LumiAPICompletion)completion;

/// Cursor-paged catalog endpoints returning full card data.
/// Endpoint: GET /stories?scope=all&fields=card&limit=100&sort=popular&cursor=...
- (void)fetchStoryCardsWithCursor:(nullable NSString *)cursor
                     completion:(LumiAPICompletion)completion;

/// Legacy ID-list + detail endpoints (kept for compatibility).
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

/// Re-generates an existing model message into a new variant.
/// Streams POST /chats/{id}/messages/{messageID}/variants.
- (LumiChatStream *)regenerateMessageWithID:(NSString *)messageID
                                     chatID:(NSString *)chatID
                               eventHandler:(void (^)(NSString *type, NSDictionary *payload))eventHandler
                                 completion:(void (^)(NSError * _Nullable error))completion;

/// PATCH /chats/{id}/messages/{messageID}. Works for user and model messages.
- (void)editMessageWithID:(NSString *)messageID
                   chatID:(NSString *)chatID
                  content:(NSString *)content
               completion:(LumiAPICompletion)completion;

/// PATCH /chats/{id}/messages/{messageID}/active-variant with a 0-based index.
- (void)setActiveVariantIndex:(NSInteger)index
                 forMessageID:(NSString *)messageID
                       chatID:(NSString *)chatID
                   completion:(nullable LumiAPICompletion)completion;

#pragma mark - Sparks & photos

/// GET /me/sparks -> { balance, tariffs }.
- (void)fetchSparksWithCompletion:(LumiAPICompletion)completion;

/// POST /chats/{id}/photo. `quality` is "standard" (fast) or "enhanced"
/// (detailed). Resolves to the created message dictionary.
- (void)generateChatPhotoForChatID:(NSString *)chatID
                           quality:(nullable NSString *)quality
                        completion:(LumiAPICompletion)completion;

@end

#pragma mark - SSE helper

@interface LumiChatStream : NSObject
- (void)start;
- (void)cancel;
@end

/// Bulk catalog helper used by LumiCatalogStore.
@interface LumiAPI (LumiCatalogDetail)
- (void)fetchCatalogDetailWithKind:(NSString *)kind
                        identifier:(NSString *)identifier
             includeFailureStatus:(BOOL)includeFailureStatus
                        completion:(LumiAPICompletion)completion;
@end

NS_ASSUME_NONNULL_END
