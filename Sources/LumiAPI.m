#import "LumiAPI.h"
#import <UIKit/UIKit.h>

NSString *const LumiAPIErrorDomain = @"com.w3rn1ght.lumi.api";
NSString *const LumiAPIDidUnauthorizedNotification = @"LumiAPIDidUnauthorizedNotification";
NSString *const LumiAuthDidChangeNotification = @"LumiAuthDidChangeNotification";

static NSString *const kAPIBaseURL = @"https://api.lumi.site";
static NSString *const kAuthBaseURL = @"https://id.lumi.site";
static NSString *const kWebOrigin = @"https://lumi.site";
static NSString *const kUserCacheKey = @"lumi.cached_user";
static NSString *const kTokenKey = @"lumi.bearer_token";
static NSString *const kRefreshKey = @"lumi.refresh_token";
static NSString *const kSessionMarkerKey = @"lumi.session_active";

static NSError *LumiError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LumiAPIErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Ошибка сети"}];
}

static NSString *LumiMessageFromPayload(id payload, NSString *fallback) {
    if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = payload;
        id message = dictionary[@"message"];
        if ([message isKindOfClass:[NSString class]] && [message length]) {
            return message;
        }
        id error = dictionary[@"error"];
        if ([error isKindOfClass:[NSString class]] && [error length]) {
            NSDictionary *known = @{
                @"validation_error": @"Проверьте введённые данные",
                @"invalid_credentials": @"Неверный email или пароль",
                @"email_not_confirmed": @"Подтвердите email — письмо уже отправлено",
                @"captcha_failed": @"Нужна проверка капчи — войдите через провайдера",
                @"Unauthorized": @"Нужно войти в аккаунт",
                @"forbidden_origin": @"Сервер отклонил запрос",
                @"rate_limited": @"Слишком много запросов, попробуйте позже",
                @"app_token_invalid": @"Ссылка входа истекла. Попробуйте снова.",
            };
            return known[error] ?: [error capitalizedString];
        }
        id detail = dictionary[@"detail"];
        if ([detail isKindOfClass:[NSString class]] && [detail length]) {
            return detail;
        }
    }
    return fallback;
}

static BOOL LumiIsSessionCookie(NSHTTPCookie *cookie) {
    if (![cookie.domain containsString:@"lumi.site"]) {
        return NO;
    }
    return [cookie.name isEqualToString:@"lumi_access_token"] ||
           [cookie.name isEqualToString:@"lumi_refresh_token"];
}

static NSString *LumiEncodeQueryValue(NSString *value) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [value stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded ?: value;
}

#pragma mark - Secure store

@implementation LumiSecureStore

+ (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

+ (void)setObject:(id)object forKey:(NSString *)key {
    NSUserDefaults *defaults = [self defaults];
    if (object) {
        [defaults setObject:object forKey:key];
    } else {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}

+ (id)objectForKey:(NSString *)key {
    return [[self defaults] objectForKey:key];
}

+ (BOOL)hasSessionMaterial {
    if ([[self defaults] boolForKey:kSessionMarkerKey]) {
        return YES;
    }
    if ([[self defaults] stringForKey:kTokenKey].length) {
        return YES;
    }
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if (LumiIsSessionCookie(cookie)) {
            return YES;
        }
    }
    return NO;
}

+ (void)markSessionActive:(BOOL)active {
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:active forKey:kSessionMarkerKey];
    [defaults synchronize];
}

+ (void)clearSession {
    NSUserDefaults *defaults = [self defaults];
    [defaults removeObjectForKey:kTokenKey];
    [defaults removeObjectForKey:kRefreshKey];
    [defaults removeObjectForKey:kSessionMarkerKey];
    [defaults removeObjectForKey:kUserCacheKey];
    [defaults synchronize];
    [[NSHTTPCookieStorage sharedHTTPCookieStorage] removeCookiesSinceDate:[NSDate distantPast]];
}

@end

#pragma mark - URL encoding

static NSString *LumiEncodePathComponent(NSString *path) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/?&=+,:%"];
    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded ?: path;
}

#pragma mark - API client

@interface LumiChatStream (LumiPrivate)
- (instancetype)initWithChatID:(NSString *)chatID
                       content:(NSString *)content
                  eventHandler:(void (^)(NSString *, NSDictionary *))eventHandler
                    completion:(void (^)(NSError *))completion;
- (instancetype)initWithChatID:(NSString *)chatID
                       path:(NSString *)path
                       body:(NSDictionary *)body
               eventHandler:(void (^)(NSString *, NSDictionary *))eventHandler
                 completion:(void (^)(NSError *))completion;
@end

@interface LumiAPI ()
@property (nonatomic, strong, readwrite, nullable) LumiSessionUser *currentUser;
@property (nonatomic, strong, readwrite, nullable) NSString *accessToken;
@property (nonatomic, strong, readwrite, nullable) NSString *refreshToken;
@property (nonatomic, strong) NSURLSession *session;
- (void)catalogFetchKind:(NSString *)kind
          identifier:(NSString *)identifier
             attempt:(NSUInteger)attempt
      completion:(LumiAPICompletion)completion;
@end

@implementation LumiAPI

+ (instancetype)sharedClient {
    static LumiAPI *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[LumiAPI alloc] init];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
        config.timeoutIntervalForRequest = 30;
        config.timeoutIntervalForResource = 60;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        self.session = [NSURLSession sessionWithConfiguration:config
                                                      delegate:nil
                                                 delegateQueue:[NSOperationQueue mainQueue]];
        [self syncCookiesFromSharedStorage];
    }
    return self;
}

- (void)syncCookiesFromSharedStorage {
    NSHTTPCookieStorage *shared = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in shared.cookies) {
        if (LumiIsSessionCookie(cookie)) {
            [self.session.configuration.HTTPCookieStorage setCookie:cookie];
        }
    }
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                      path:(NSString *)path
                                   baseURL:(NSString *)baseURL
                                      body:(nullable id)body
                                 timeout:(NSTimeInterval)timeout {
    NSString *urlString = [NSString stringWithFormat:@"%@%@", baseURL, path];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                     timeoutInterval:timeout];
    request.HTTPMethod = method;
    NSMutableDictionary *headers = [@{
        @"Accept": @"application/json",
        @"Content-Type": @"application/json",
        @"User-Agent": @"Lumi-iOS/1.5.3",
        @"Origin": kWebOrigin,
    } mutableCopy];
    if (self.accessToken.length) {
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", self.accessToken];
    }
    request.allHTTPHeaderFields = headers;
    if (body) {
        NSError *jsonError = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    }
    return request;
}

- (void)performRequest:(NSURLRequest *)request
        completion:(LumiAPICompletion)completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        id json = nil;
        if (data.length) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        }
        NSInteger status = [http isKindOfClass:[NSHTTPURLResponse class]] ? http.statusCode : 0;
        NSString *path = request.URL.path ?: @"";
        NSLog(@"[Lumi] %@ %@ -> %ld %@", request.HTTPMethod, path, (long)status,
              error ? error.localizedDescription : @"");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, error);
                return;
            }
            if (status >= 200 && status < 300) {
                [self captureTokensFromPayload:json];
                completion(json ?: @{}, nil);
                return;
            }
            if (status == 401) {
                [LumiSecureStore markSessionActive:NO];
                [[NSNotificationCenter defaultCenter] postNotificationName:LumiAPIDidUnauthorizedNotification
                                                                    object:nil];
            }
            NSString *message = LumiMessageFromPayload(json,
                                                       [NSString stringWithFormat:@"Ошибка сервера (%ld)", (long)status]);
            completion(json, LumiError(status, message));
        });
    }];
    [task resume];
}

#pragma mark - Session

- (void)refreshSessionWithCompletion:(void (^)(BOOL))completion {
    [self syncCookiesFromSharedStorage];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:@"/auth/me"
                                                   baseURL:kAuthBaseURL
                                                      body:nil
                                                   timeout:20.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSDictionary *user = dictionary[@"user"];
        if (!error && [user isKindOfClass:[NSDictionary class]]) {
            [self setCurrentUserJSON:user];
            completion(YES);
            return;
        }
        if (error.code == 401) {
            [LumiSecureStore markSessionActive:NO];
        }
        completion(NO);
    }];
}

- (void)loginWithEmail:(NSString *)email
               password:(NSString *)password
             completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                      path:@"/auth/login"
                                                   baseURL:kAuthBaseURL
                                                      body:@{@"email": email ?: @"", @"password": password ?: @""}
                                                   timeout:30.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (error) {
            completion(result, error);
            return;
        }
        NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSDictionary *user = dictionary[@"user"];
        if ([user isKindOfClass:[NSDictionary class]]) {
            [self setCurrentUserJSON:user];
            completion(result, nil);
            return;
        }
        completion(result, LumiError(0, @"Неверный ответ сервера"));
    }];
}

- (void)logoutWithCompletion:(void (^)(void))completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                      path:@"/auth/logout"
                                                   baseURL:kAuthBaseURL
                                                      body:nil
                                                   timeout:20.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        [LumiSecureStore clearSession];
        self.currentUser = nil;
        self.accessToken = nil;
        self.refreshToken = nil;
        completion();
    }];
}

- (BOOL)isAuthenticated {
    return self.currentUser != nil || [LumiSecureStore hasSessionMaterial];
}

- (void)setCurrentUserJSON:(NSDictionary *)user {
    self.currentUser = [LumiSessionUser userFromJSON:user];
    [LumiSecureStore markSessionActive:YES];
}

- (void)captureTokensFromPayload:(nullable NSDictionary *)payload {
    if (!payload) return;
    if (payload[@"access_token"]) {
        self.accessToken = payload[@"access_token"];
        [LumiSecureStore setObject:self.accessToken forKey:kTokenKey];
    }
    if (payload[@"refresh_token"]) {
        self.refreshToken = payload[@"refresh_token"];
        [LumiSecureStore setObject:self.refreshToken forKey:kRefreshKey];
    }
}

#pragma mark - Catalog

- (void)fetchCharacterCardsWithCursor:(NSString *)cursor
                     completion:(LumiAPICompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/characters?scope=all&fields=card&limit=100&sort=popular%@",
                      cursor ? [NSString stringWithFormat:@"&cursor=%@", LumiEncodeQueryValue(cursor)] : @""];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:path
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:40.0];
    [self performRequest:request completion:completion];
}

- (void)fetchStoryCardsWithCursor:(NSString *)cursor
                   completion:(LumiAPICompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/stories?scope=all&fields=card&limit=100&sort=popular%@",
                      cursor ? [NSString stringWithFormat:@"&cursor=%@", LumiEncodeQueryValue(cursor)] : @""];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:path
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:40.0];
    [self performRequest:request completion:completion];
}

- (void)fetchCharacterCardsWithCursor:(NSString *)cursor
                               limit:(NSInteger)limit
                      completion:(LumiAPICompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/characters?scope=all&fields=card&limit=%ld&sort=popular%@",
                      (long)limit,
                      cursor ? [NSString stringWithFormat:@"&cursor=%@", LumiEncodeQueryValue(cursor)] : @""];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:path
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:40.0];
    [self performRequest:request completion:completion];
}

- (void)fetchStoryCardsWithCursor:(NSString *)cursor
                           limit:(NSInteger)limit
                      completion:(LumiAPICompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/stories?scope=all&fields=card&limit=%ld&sort=popular%@",
                      (long)limit,
                      cursor ? [NSString stringWithFormat:@"&cursor=%@", LumiEncodeQueryValue(cursor)] : @""];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:path
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:40.0];
    [self performRequest:request completion:completion];
}

- (void)fetchCharacterWithID:(NSString *)characterID completion:(LumiAPICompletion)completion {
    [self fetchDetailWithPublicPath:[NSString stringWithFormat:@"/public/characters/%@", characterID]
              authenticatedPath:[NSString stringWithFormat:@"/characters/%@", characterID]
                     completion:completion];
}

- (void)fetchStoryWithID:(NSString *)storyID completion:(LumiAPICompletion)completion {
    [self fetchDetailWithPublicPath:[NSString stringWithFormat:@"/public/stories/%@", storyID]
              authenticatedPath:[NSString stringWithFormat:@"/stories/%@", storyID]
                     completion:completion];
}

- (void)fetchDetailWithPublicPath:(NSString *)publicPath
            authenticatedPath:(NSString *)authenticatedPath
                   completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:publicPath
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:25.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (!error && [result isKindOfClass:[NSDictionary class]]) {
            completion(result, nil);
            return;
        }
        if (error && error.code == 404) {
            NSMutableURLRequest *retry = [self requestWithMethod:@"GET"
                                                           path:authenticatedPath
                                                        baseURL:kAPIBaseURL
                                                           body:nil
                                                        timeout:25.0];
            [self performRequest:retry completion:^(id retryResult, NSError *retryError) {
                if (!retryError && [retryResult isKindOfClass:[NSDictionary class]]) {
                    completion(retryResult, nil);
                    return;
                }
                completion(nil, retryError ?: error);
            }];
            return;
        }
        completion(nil, error);
    }];
}

- (void)fetchTagsWithCompletion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:@"/tags"
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:20.0];
    [self performRequest:request completion:completion];
}

- (void)fetchCharactersWithQuery:(NSString *)query
                           tag:(NSString *)tag
                      completion:(LumiAPICompletion)completion {
    NSMutableArray *params = [NSMutableArray array];
    if (query.length) [params addObject:[NSString stringWithFormat:@"q=%@", LumiEncodeQueryValue(query)]];
    if (tag.length && ![tag isEqualToString:@"Все"]) [params addObject:[NSString stringWithFormat:@"tag=%@", LumiEncodeQueryValue(tag)]];
    [params addObject:@"scope=all"];
    [params addObject:@"fields=card"];
    [params addObject:@"limit=100"];
    [params addObject:@"sort=popular"];
    NSString *path = [NSString stringWithFormat:@"/characters?%@", [params componentsJoinedByString:@"&"]];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:path
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:completion];
}

- (void)fetchStoriesWithQuery:(NSString *)query
                          tag:(NSString *)tag
                     completion:(LumiAPICompletion)completion {
    NSMutableArray *params = [NSMutableArray array];
    if (query.length) [params addObject:[NSString stringWithFormat:@"q=%@", LumiEncodeQueryValue(query)]];
    if (tag.length && ![tag isEqualToString:@"Все"]) [params addObject:[NSString stringWithFormat:@"tag=%@", LumiEncodeQueryValue(tag)]];
    [params addObject:@"scope=all"];
    [params addObject:@"fields=card"];
    [params addObject:@"limit=100"];
    [params addObject:@"sort=popular"];
    NSString *path = [NSString stringWithFormat:@"/stories?%@", [params componentsJoinedByString:@"&"]];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:path
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:completion];
}

#pragma mark - Chats

- (void)fetchChatsWithCompletion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:@"/chats"
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (error) {
            completion(result, error);
            return;
        }
        NSArray *items = [result isKindOfClass:[NSDictionary class]] ? result[@"items"] : nil;
        if (![items isKindOfClass:[NSArray class]] && [result isKindOfClass:[NSArray class]]) {
            items = result;
        }
        completion([items isKindOfClass:[NSArray class]] ? items : @[], nil);
    }];
}

- (void)fetchChatWithID:(NSString *)chatID completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                      path:[NSString stringWithFormat:@"/chats/%@", chatID]
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:completion];
}

- (void)sendMessageToChatID:(NSString *)chatID
                     content:(NSString *)content
                    isContinue:(BOOL)isContinue
                  completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                      path:[NSString stringWithFormat:@"/chats/%@/messages", chatID]
                                                   baseURL:kAPIBaseURL
                                                      body:@{@"content": content ?: @"", @"is_continue": @(isContinue)}
                                                   timeout:60.0];
    [self performRequest:request completion:completion];
}

- (void)deleteChat:(NSString *)chatID completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"DELETE"
                                                      path:[NSString stringWithFormat:@"/chats/%@", chatID]
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:completion];
}

- (void)deleteMessageWithID:(NSString *)messageID completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"DELETE"
                                                      path:[NSString stringWithFormat:@"/messages/%@", messageID]
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:completion];
}

- (void)forkChatFromMessageID:(NSString *)messageID completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                      path:[NSString stringWithFormat:@"/messages/%@/fork", messageID]
                                                   baseURL:kAPIBaseURL
                                                      body:nil
                                                   timeout:30.0];
    [self performRequest:request completion:completion];
}

#pragma mark - Chat streams

- (void)openChatStreamWithID:(NSString *)chatID
                      path:(NSString *)path
                      body:(NSDictionary *)body
                 eventHandler:(void (^)(NSString *, NSDictionary *))eventHandler
                   completion:(void (^)(NSError *))completion {
    LumiChatStream *stream = [[LumiChatStream alloc] initWithChatID:chatID
                                                               path:path
                                                               body:body
                                                        eventHandler:eventHandler
                                                      completion:completion];
    [stream open];
}

- (void)openChatStreamWithID:(NSString *)chatID
                     content:(NSString *)content
                eventHandler:(void (^)(NSString *, NSDictionary *))eventHandler
                  completion:(void (^)(NSError *))completion {
    LumiChatStream *stream = [[LumiChatStream alloc] initWithChatID:chatID
                                                           content:content
                                                    eventHandler:eventHandler
                                                      completion:completion];
    [stream open];
}

@end

#pragma mark - LumiSessionUser implementation

@implementation LumiSessionUser

+ (instancetype)userFromJSON:(NSDictionary *)json {
    LumiSessionUser *user = [[LumiSessionUser alloc] init];
    user.userID = [json[@"id"] isKindOfClass:[NSString class]] ? json[@"id"] : [json[@"id"] stringValue];
    user.email = json[@"email"];
    user.username = json[@"username"];
    user.avatarURL = json[@"avatar_url"];
    return user;
}

- (NSString *)displayName {
    return self.username ?: self.email ?: self.userID ?: @"Unknown";
}

@end