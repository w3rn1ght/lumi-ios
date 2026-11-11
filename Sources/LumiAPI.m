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
    [[self defaults] setBool:active forKey:kSessionMarkerKey];
    [[self defaults] synchronize];
}

+ (void)clearSession {
    NSUserDefaults *defaults = [self defaults];
    [defaults removeObjectForKey:kTokenKey];
    [defaults removeObjectForKey:kRefreshKey];
    [defaults removeObjectForKey:kUserCacheKey];
    [defaults removeObjectForKey:kSessionMarkerKey];
    [defaults synchronize];
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies]) {
        if (LumiIsSessionCookie(cookie)) {
            [storage deleteCookie:cookie];
        }
    }
}

@end

#pragma mark - User

@implementation LumiSessionUser

+ (instancetype)userFromJSON:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    LumiSessionUser *user = [[LumiSessionUser alloc] init];
    id identifier = json[@"id"] ?: json[@"user_id"];
    user.userID = [identifier isKindOfClass:[NSString class]] ? identifier : @"";
    id email = json[@"email"];
    user.email = [email isKindOfClass:[NSString class]] ? email : nil;
    id username = json[@"username"] ?: json[@"name"] ?: json[@"display_name"];
    user.username = [username isKindOfClass:[NSString class]] ? username : nil;
    id avatar = json[@"avatar_url"] ?: json[@"avatar"];
    user.avatarURL = [avatar isKindOfClass:[NSString class]] ? avatar : nil;
    return user;
}

- (NSString *)displayName {
    if (self.username.length) {
        return self.username;
    }
    if (self.email.length) {
        return self.email;
    }
    return @"Аккаунт";
}

@end

#pragma mark - Path encoding

static NSString *LumiEncodePath(NSString *path) {
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
@end

@interface LumiAPI ()
@property (nonatomic, strong, readwrite, nullable) LumiSessionUser *currentUser;
@property (nonatomic, strong, readwrite, nullable) NSString *accessToken;
@property (nonatomic, strong, readwrite, nullable) NSString *refreshToken;
@property (nonatomic, strong) NSURLSession *session;
- (void)fetchCatalogDetailWithKind:(NSString *)kind
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
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 20.0;
        configuration.timeoutIntervalForResource = 40.0;
        configuration.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        configuration.HTTPShouldSetCookies = YES;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.HTTPMaximumConnectionsPerHost = 6;
        configuration.HTTPAdditionalHeaders = @{
            @"Accept": @"application/json",
            @"Accept-Language": @"ru,en;q=0.8",
            @"X-Lang": @"ru",
            @"Origin": kWebOrigin,
            @"Referer": [kWebOrigin stringByAppendingString:@"/"],
            @"X-Lumi-Client": @"ios-app",
        };
        _session = [NSURLSession sessionWithConfiguration:configuration];

        _accessToken = [LumiSecureStore objectForKey:kTokenKey];
        _refreshToken = [LumiSecureStore objectForKey:kRefreshKey];
        NSDictionary *cached = [LumiSecureStore objectForKey:kUserCacheKey];
        if ([cached isKindOfClass:[NSDictionary class]]) {
            _currentUser = [LumiSessionUser userFromJSON:cached];
        }
    }
    return self;
}

- (BOOL)isAuthenticated {
    return [LumiSecureStore hasSessionMaterial];
}

- (NSArray<NSHTTPCookie *> *)lumiCookies {
    NSMutableArray *result = [NSMutableArray array];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        if ([cookie.domain containsString:@"lumi.site"]) {
            [result addObject:cookie];
        }
    }
    return result;
}

- (void)syncCookiesFromSharedStorage {
    NSArray *cookies = [self lumiCookies];
    BOOL hasSession = NO;
    for (NSHTTPCookie *cookie in cookies) {
        if (LumiIsSessionCookie(cookie)) {
            hasSession = YES;
            break;
        }
    }
    if (hasSession) {
        [LumiSecureStore markSessionActive:YES];
    }
    NSLog(@"[Lumi] cookies=%lu session=%d", (unsigned long)cookies.count, hasSession);
}

- (void)storeCookies:(NSArray<NSHTTPCookie *> *)cookies {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSInteger stored = 0;
    for (NSHTTPCookie *cookie in cookies) {
        if (![cookie.domain containsString:@"lumi.site"]) {
            continue;
        }
        [storage setCookie:cookie];
        if (LumiIsSessionCookie(cookie)) {
            [LumiSecureStore markSessionActive:YES];
        }
        stored++;
    }
    NSLog(@"[Lumi] imported %ld cookies", (long)stored);
}

- (void)captureTokensFromPayload:(id)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dictionary = payload;
    id access = dictionary[@"access"];
    if (![access isKindOfClass:[NSString class]]) {
        access = dictionary[@"access_token"];
    }
    if (![access isKindOfClass:[NSString class]]) {
        access = dictionary[@"token"];
    }
    if ([access isKindOfClass:[NSString class]] && [access length] > 10) {
        self.accessToken = access;
        [LumiSecureStore setObject:access forKey:kTokenKey];
        [LumiSecureStore markSessionActive:YES];
    }
    id refresh = dictionary[@"refresh"];
    if (![refresh isKindOfClass:[NSString class]]) {
        refresh = dictionary[@"refresh_token"];
    }
    if ([refresh isKindOfClass:[NSString class]] && [refresh length] > 10) {
        self.refreshToken = refresh;
        [LumiSecureStore setObject:refresh forKey:kRefreshKey];
    }
}

- (void)setCurrentUserJSON:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSMutableDictionary *cleaned = [NSMutableDictionary dictionary];
    for (NSString *key in json) {
        id value = json[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
            cleaned[key] = value;
        }
    }
    [LumiSecureStore setObject:cleaned forKey:kUserCacheKey];
    [LumiSecureStore markSessionActive:YES];
    self.currentUser = [LumiSessionUser userFromJSON:cleaned];
}

#pragma mark - Requests

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                      path:(NSString *)path
                                   baseURL:(NSString *)baseURL
                                      body:(id)body
                                   timeout:(NSTimeInterval)timeout {
    NSString *full = [baseURL stringByAppendingString:LumiEncodePath(path)];
    NSURL *url = [NSURL URLWithString:full];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = timeout;
    [request setValue:kWebOrigin forHTTPHeaderField:@"Origin"];
    [request setValue:[kWebOrigin stringByAppendingString:@"/"] forHTTPHeaderField:@"Referer"];
    if (self.accessToken.length) {
        [request setValue:[@"Bearer " stringByAppendingString:self.accessToken] forHTTPHeaderField:@"Authorization"];
    }
    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
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
                                                  baseURL:kAPIBaseURL
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
        }
        [self refreshSessionWithCompletion:^(BOOL ok) {
            completion(dictionary ?: @{}, ok ? nil : LumiError(401, @"Не удалось проверить сессию"));
        }];
    }];
}

- (void)exchangeAppToken:(NSString *)token completion:(void (^)(NSError *))completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/auth/app/exchange"
                                                  baseURL:kAPIBaseURL
                                                     body:@{@"token": token ?: @""}
                                                  timeout:30.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (error) {
            completion(error);
            return;
        }
        NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : nil;
        NSDictionary *user = dictionary[@"user"];
        if ([user isKindOfClass:[NSDictionary class]]) {
            [self setCurrentUserJSON:user];
        }
        [self syncCookiesFromSharedStorage];
        completion(nil);
    }];
}

- (void)logout {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/auth/logout"
                                                  baseURL:kAuthBaseURL
                                                     body:@{}
                                                  timeout:15.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        NSLog(@"[Lumi] logout: %@", error ?: @"ok");
    }];
    [LumiSecureStore clearSession];
    self.currentUser = nil;
    self.accessToken = nil;
    self.refreshToken = nil;
}

#pragma mark - Catalog

- (void)fetchCharacterIDsWithCompletion:(LumiAPICompletion)completion {
    [self fetchIDListWithPublicPath:@"/public/characters?limit=1000"
                    authenticatedPath:@"/characters?limit=1000"
                         completion:completion];
}

- (void)fetchStoryIDsWithCompletion:(LumiAPICompletion)completion {
    [self fetchIDListWithPublicPath:@"/public/stories?limit=1000"
                    authenticatedPath:@"/stories?limit=1000"
                         completion:completion];
}

- (void)fetchIDListWithPublicPath:(NSString *)publicPath
                authenticatedPath:(NSString *)authenticatedPath
                       completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                     path:publicPath
                                                  baseURL:kAPIBaseURL
                                                     body:nil
                                                  timeout:40.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        id items = [result isKindOfClass:[NSDictionary class]] ? result[@"items"] : nil;
        if ([items isKindOfClass:[NSArray class]]) {
            completion(items, nil);
            return;
        }
        BOOL shouldRetryAuthenticated = (error.code == 401 || error.code == 403) && [self isAuthenticated];
        if (!shouldRetryAuthenticated) {
            completion(nil, error ?: LumiError(500, @"Не удалось загрузить каталог"));
            return;
        }
        NSMutableURLRequest *retry = [self requestWithMethod:@"GET"
                                                       path:authenticatedPath
                                                    baseURL:kAPIBaseURL
                                                       body:nil
                                                    timeout:40.0];
        [self performRequest:retry completion:^(id retryResult, NSError *retryError) {
            id retryItems = [retryResult isKindOfClass:[NSDictionary class]] ? retryResult[@"items"] : nil;
            if ([retryItems isKindOfClass:[NSArray class]]) {
                completion(retryItems, nil);
                return;
            }
            completion(nil, retryError ?: LumiError(500, @"Не удалось загрузить каталог"));
        }];
    }];
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
        if (error.code == 429) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self fetchDetailWithPublicPath:publicPath
                              authenticatedPath:authenticatedPath
                                     completion:completion];
            });
            return;
        }
        if ((error.code == 401 || error.code == 403) && [self isAuthenticated]) {
            NSMutableURLRequest *retry = [self requestWithMethod:@"GET"
                                                           path:authenticatedPath
                                                        baseURL:kAPIBaseURL
                                                           body:nil
                                                        timeout:25.0];
            [self performRequest:retry completion:completion];
            return;
        }
        completion(result, error);
    }];
}

#pragma mark - Catalog detail (off-main)

/// Bulk catalog loading issues ~1400 requests. The generic `performRequest:`
/// always hops to the main queue, which turned the detail download into a
/// crawl and froze the progress bar. This variant parses and delivers on the
/// session's own queue, retries a bounded number of times and never retries
/// forever (the old 429 path could loop indefinitely).
- (void)fetchCatalogDetailWithKind:(NSString *)kind
                        identifier:(NSString *)identifier
             includeFailureStatus:(BOOL)includeFailureStatus
                        completion:(LumiAPICompletion)completion {
    [self fetchCatalogDetailWithKind:kind
                          identifier:identifier
                             attempt:0
                          completion:completion];
}

- (void)fetchCatalogDetailWithKind:(NSString *)kind
                        identifier:(NSString *)identifier
                           attempt:(NSUInteger)attempt
                        completion:(LumiAPICompletion)completion {
    if (!completion) {
        return;
    }
    NSString *path = [NSString stringWithFormat:@"/public/%@/%@", kind, identifier];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                     path:path
                                                  baseURL:kAPIBaseURL
                                                     body:nil
                                                  timeout:10.0];
    // Public catalog payloads never depend on the account: dropping the bearer
    // token keeps the auth middleware out of a 1000-request crawl.
    [request setValue:nil forHTTPHeaderField:@"Authorization"];

    __block BOOL settled = NO;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (settled) {
            return;
        }
        settled = YES;
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = http ? http.statusCode : 0;
        id json = nil;
        if (data.length) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        }
        if (!error && status >= 200 && status < 300 && [json isKindOfClass:[NSDictionary class]]) {
            completion(json, nil);
            return;
        }

        BOOL cancelled = (error.code == NSURLErrorCancelled);
        NSUInteger maxAttempts = 4;
        BOOL retryable = (error != nil || status == 429 || status >= 500 || status == 0);
        if (retryable && attempt + 1 < maxAttempts) {
            double delay = 0.35 + 0.35 * (double)attempt;
            if (status == 429) {
                delay = (double)(1 << MIN(attempt, (NSUInteger)4));
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self fetchCatalogDetailWithKind:kind
                                      identifier:identifier
                                         attempt:attempt + 1
                                      completion:completion];
            });
            return;
        }

        NSString *message = status ? [NSString stringWithFormat:@"HTTP %ld", (long)status]
                                   : (cancelled ? @"Тайм-аут соединения" : (error.localizedDescription ?: @"Сетевая ошибка"));
        completion(json, LumiError(status ?: (cancelled ? 408 : 500), message));
    }];
    [task resume];

    // iOS sometimes keeps a dead TLS handshake "alive" forever (HTTP/2 pings
    // stop the idle timer), so a request can hang for minutes while occupying
    // one of the few connection slots. Cancel it ourselves and let the retry
    // path open a fresh connection.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(9.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!settled) {
            [task cancel];
        }
    });
}

- (void)fetchTagsWithCompletion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                     path:@"/tags"
                                                  baseURL:kAPIBaseURL
                                                     body:nil
                                                  timeout:25.0];
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
                                                  timeout:25.0];
    [self performRequest:request completion:completion];
}

- (void)openChatWithCharacterID:(NSString *)characterID
                        storyID:(NSString *)storyID
                     completion:(LumiAPICompletion)completion {
    NSMutableArray *bodies = [NSMutableArray array];
    NSString *kind = characterID.length ? @"character" : @"story";
    NSString *target = characterID.length ? characterID : storyID;
    if (!target.length) {
        completion(nil, LumiError(400, @"Не выбран персонаж"));
        return;
    }
    if (characterID.length) {
        [bodies addObject:@{@"character_id": characterID}];
    } else {
        [bodies addObject:@{@"story_id": storyID}];
    }
    [bodies addObject:@{@"target_kind": kind, @"target_id": target}];
    [bodies addObject:@{@"kind": kind, @"target_id": target}];
    [bodies addObject:@{@"target_type": kind, @"target_id": target}];
    [self attemptOpenChatWithBodies:bodies index:0 completion:completion];
}

- (void)attemptOpenChatWithBodies:(NSArray<NSDictionary *> *)bodies
                            index:(NSUInteger)index
                       completion:(LumiAPICompletion)completion {
    if (index >= bodies.count) {
        completion(nil, LumiError(400, @"Не удалось открыть чат"));
        return;
    }
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/chats/open"
                                                  baseURL:kAPIBaseURL
                                                     body:bodies[index]
                                                  timeout:40.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (!error) {
            NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : nil;
            NSDictionary *chat = dictionary[@"chat"];
            if (![chat isKindOfClass:[NSDictionary class]]) {
                chat = dictionary;
            }
            if ([chat[@"id"] isKindOfClass:[NSString class]]) {
                completion(chat, nil);
                return;
            }
        }
        if (error.code == 401) {
            completion(result, error);
            return;
        }
        [self attemptOpenChatWithBodies:bodies index:index + 1 completion:completion];
    }];
}

- (void)fetchMessagesForChatID:(NSString *)chatID
                         limit:(NSInteger)limit
                        before:(NSString *)before
                    completion:(LumiAPICompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/chats/%@/messages?limit=%ld", chatID, (long)limit];
    if (before.length) {
        path = [path stringByAppendingFormat:@"&before=%@", before];
    }
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                     path:path
                                                  baseURL:kAPIBaseURL
                                                     body:nil
                                                  timeout:40.0];
    [self performRequest:request completion:completion];
}

- (void)markChatRead:(NSString *)chatID {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:[NSString stringWithFormat:@"/chats/%@/read", chatID]
                                                  baseURL:kAPIBaseURL
                                                     body:@{}
                                                  timeout:20.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (error) {
            NSLog(@"[Lumi] mark read failed: %@", error.localizedDescription);
        }
    }];
}

- (void)seedIntroForChat:(NSString *)chatID completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:[NSString stringWithFormat:@"/chats/%@/seed-intro", chatID]
                                                  baseURL:kAPIBaseURL
                                                     body:@{}
                                                  timeout:120.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (completion) {
            completion(result, error);
        }
    }];
}

- (void)deleteChat:(NSString *)chatID completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"DELETE"
                                                     path:[NSString stringWithFormat:@"/chats/%@", chatID]
                                                  baseURL:kAPIBaseURL
                                                     body:nil
                                                  timeout:25.0];
    [self performRequest:request completion:^(id result, NSError *error) {
        if (completion) {
            completion(result, error);
        }
    }];
}

- (LumiChatStream *)sendMessage:(NSString *)content
                         chatID:(NSString *)chatID
                   eventHandler:(void (^)(NSString *, NSDictionary *))eventHandler
                     completion:(void (^)(NSError *))completion {
    LumiChatStream *stream = [[LumiChatStream alloc] initWithChatID:chatID
                                                            content:content
                                                       eventHandler:eventHandler
                                                         completion:completion];
    [stream start];
    return stream;
}

@end

#pragma mark - SSE stream

@interface LumiChatStream () <NSURLSessionDataDelegate>
@property (nonatomic, copy) NSString *chatID;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) void (^eventHandler)(NSString *, NSDictionary *);
@property (nonatomic, copy) void (^completion)(NSError *);
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) NSInteger errorStatus;
@end

@implementation LumiChatStream

- (instancetype)initWithChatID:(NSString *)chatID
                       content:(NSString *)content
                  eventHandler:(void (^)(NSString *, NSDictionary *))eventHandler
                    completion:(void (^)(NSError *))completion {
    self = [super init];
    if (self) {
        _chatID = [chatID copy];
        _content = [content copy];
        _eventHandler = [eventHandler copy];
        _completion = [completion copy];
        _buffer = [NSMutableData data];
    }
    return self;
}

- (void)start {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 120.0;
    configuration.timeoutIntervalForResource = 300.0;
    configuration.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    configuration.HTTPShouldSetCookies = YES;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];

    NSString *urlString = [NSString stringWithFormat:@"%@/chats/%@/messages", kAPIBaseURL, self.chatID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 180.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    [request setValue:@"ru" forHTTPHeaderField:@"X-Lang"];
    [request setValue:kWebOrigin forHTTPHeaderField:@"Origin"];
    [request setValue:[kWebOrigin stringByAppendingString:@"/"] forHTTPHeaderField:@"Referer"];
    [request setValue:@"ios-app" forHTTPHeaderField:@"X-Lumi-Client"];
    NSString *token = [LumiAPI sharedClient].accessToken;
    if (token.length) {
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    }
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"content": self.content ?: @""}
                                                      options:0 error:NULL];
    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];
}

- (void)cancel {
    [self finishWithError:nil];
}

- (void)finishWithError:(NSError *)error {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self.task cancel];
    [self.session invalidateAndCancel];
    void (^completion)(NSError *) = self.completion;
    self.completion = nil;
    self.eventHandler = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(error);
        }
    });
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if ([http isKindOfClass:[NSHTTPURLResponse class]] && http.statusCode >= 400) {
        self.errorStatus = http.statusCode;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.buffer appendData:data];
    if (self.errorStatus == 0) {
        [self drainBuffer];
    }
}

- (void)drainBuffer {
    while (YES) {
        NSRange separator = [self.buffer rangeOfData:[@"\n\n" dataUsingEncoding:NSUTF8StringEncoding]
                                             options:0
                                               range:NSMakeRange(0, self.buffer.length)];
        if (separator.location == NSNotFound) {
            break;
        }
        NSData *chunk = [self.buffer subdataWithRange:NSMakeRange(0, separator.location)];
        [self.buffer replaceBytesInRange:NSMakeRange(0, separator.location + separator.length) withBytes:NULL length:0];
        NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        if (text.length) {
            [self handleEventText:text];
        }
    }
}

- (void)handleEventText:(NSString *)text {
    NSString *event = @"message";
    NSMutableArray<NSString *> *dataLines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"event:"]) {
            event = [[line substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        } else if ([line hasPrefix:@"data:"]) {
            [dataLines addObject:[[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
    }
    if (!dataLines.count) {
        return;
    }
    NSData *jsonData = [[dataLines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    id payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
    NSDictionary *dictionary = [payload isKindOfClass:[NSDictionary class]] ? payload : @{};
    void (^handler)(NSString *, NSDictionary *) = self.eventHandler;
    if (!handler) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(event, dictionary);
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.errorStatus > 0) {
        id payload = self.buffer.length ? [NSJSONSerialization JSONObjectWithData:self.buffer options:0 error:NULL] : nil;
        NSString *message = LumiMessageFromPayload(payload, @"Не удалось отправить сообщение");
        [self finishWithError:LumiError(self.errorStatus, message)];
        return;
    }
    [self finishWithError:error];
}

@end
