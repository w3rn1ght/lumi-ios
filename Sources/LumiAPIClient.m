#import "LumiAPIClient.h"

NSString *const LumiAPIErrorDomain = @"com.w3rn1ght.lumi.api";

static NSString *const kNativeBaseURL = @"https://lumi-api.nexoragroup.dev";
static NSString *const kPublicBaseURL = @"https://api.lumi.site";
static NSString *const kAccessTokenKey = @"lumi.access_token";
static NSString *const kRefreshTokenKey = @"lumi.refresh_token";
static NSString *const kUserEmailKey = @"lumi.user_email";

@interface LumiAPIClient ()
@property (nonatomic, copy, readwrite, nullable) NSString *accessToken;
@property (nonatomic, copy, readwrite, nullable) NSString *refreshToken;
@property (nonatomic, copy, readwrite, nullable) NSString *userEmail;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation LumiAPIClient

+ (instancetype)sharedClient {
    static LumiAPIClient *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [[LumiAPIClient alloc] init];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 30.0;
        configuration.timeoutIntervalForResource = 60.0;
        configuration.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Lumi/1.0.0 (iOS)",
            @"Accept": @"application/json",
        };
        _session = [NSURLSession sessionWithConfiguration:configuration];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _accessToken = [defaults stringForKey:kAccessTokenKey];
        _refreshToken = [defaults stringForKey:kRefreshTokenKey];
        _userEmail = [defaults stringForKey:kUserEmailKey];
    }
    return self;
}

- (BOOL)isAuthenticated {
    return self.accessToken.length > 0;
}

- (void)logout {
    self.accessToken = nil;
    self.refreshToken = nil;
    self.userEmail = nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kAccessTokenKey];
    [defaults removeObjectForKey:kRefreshTokenKey];
    [defaults removeObjectForKey:kUserEmailKey];
    [defaults synchronize];
}

#pragma mark - Request helpers

- (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:LumiAPIErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Ошибка сети"}];
}

- (NSString *)messageFromErrorJSON:(id)json fallback:(NSString *)fallback {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return fallback;
    }
    NSDictionary *dictionary = json;
    id detail = dictionary[@"detail"];
    if ([detail isKindOfClass:[NSString class]] && [detail length]) {
        return detail;
    }
    if ([detail isKindOfClass:[NSArray class]]) {
        return [[detail firstObject] description] ?: fallback;
    }
    id message = dictionary[@"message"];
    if ([message isKindOfClass:[NSString class]] && [message length]) {
        return message;
    }
    for (NSString *key in dictionary) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSArray class]] && [value count]) {
            return [NSString stringWithFormat:@"%@: %@", key, [value firstObject]];
        }
        if ([value isKindOfClass:[NSString class]] && [value length]) {
            return [NSString stringWithFormat:@"%@: %@", key, value];
        }
    }
    return fallback;
}

- (void)performRequest:(NSURLRequest *)request
            completion:(LumiAPIRawCompletion)completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, error);
                return;
            }
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            id json = nil;
            if (data.length) {
                json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            }
            if (http.statusCode >= 200 && http.statusCode < 300) {
                if (!json) {
                    json = @{};
                }
                completion([json isKindOfClass:[NSDictionary class]] ? json : @{@"data": json}, nil);
                return;
            }
            NSString *message = [self messageFromErrorJSON:json
                                                  fallback:[NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]];
            NSError *apiError = [self errorWithMessage:message code:http.statusCode];
            completion([json isKindOfClass:[NSDictionary class]] ? json : nil, apiError);
        });
    }];
    [task resume];
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method
                                      path:(NSString *)path
                                   baseURL:(NSString *)baseURL
                                      body:(id)body
                                 needsAuth:(BOOL)needsAuth {
    NSURL *url = [NSURL URLWithString:[baseURL stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"ru" forHTTPHeaderField:@"X-Lang"];
    if (needsAuth && self.accessToken.length) {
        [request setValue:[@"Bearer " stringByAppendingString:self.accessToken]
       forHTTPHeaderField:@"Authorization"];
    }
    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    }
    return request;
}

#pragma mark - Auth

- (void)storeTokens:(NSDictionary *)json email:(NSString *)email {
    NSString *access = json[@"access"];
    NSString *refresh = json[@"refresh"];
    if ([access isKindOfClass:[NSString class]] && access.length) {
        self.accessToken = access;
        [[NSUserDefaults standardUserDefaults] setObject:access forKey:kAccessTokenKey];
    }
    if ([refresh isKindOfClass:[NSString class]] && refresh.length) {
        self.refreshToken = refresh;
        [[NSUserDefaults standardUserDefaults] setObject:refresh forKey:kRefreshTokenKey];
    }
    if (email.length) {
        self.userEmail = email;
        [[NSUserDefaults standardUserDefaults] setObject:email forKey:kUserEmailKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)loginWithEmail:(NSString *)email
              password:(NSString *)password
            completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/api/users/login/"
                                                  baseURL:kNativeBaseURL
                                                     body:@{@"email": email, @"password": password}
                                                needsAuth:NO];
    [self performRequest:request completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        [self storeTokens:json email:email];
        completion(json, nil);
    }];
}

- (void)registerWithEmail:(NSString *)email
                 password:(NSString *)password
               completion:(LumiAPICompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/api/users/register/"
                                                  baseURL:kNativeBaseURL
                                                     body:@{@"email": email, @"password": password}
                                                needsAuth:NO];
    [self performRequest:request completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if ([json[@"access"] isKindOfClass:[NSString class]]) {
            [self storeTokens:json email:email];
        }
        completion(json, nil);
    }];
}

- (void)refreshIfNeededWithCompletion:(void (^)(BOOL))completion {
    if (!self.refreshToken.length) {
        completion(NO);
        return;
    }
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/api/users/token/refresh/"
                                                  baseURL:kNativeBaseURL
                                                     body:@{@"refresh": self.refreshToken}
                                                needsAuth:NO];
    [self performRequest:request completion:^(NSDictionary *json, NSError *error) {
        if (error || ![json[@"access"] isKindOfClass:[NSString class]]) {
            completion(NO);
            return;
        }
        self.accessToken = json[@"access"];
        [[NSUserDefaults standardUserDefaults] setObject:self.accessToken forKey:kAccessTokenKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        completion(YES);
    }];
}

#pragma mark - Authed native API

- (void)authorizedRequest:(NSString *)method
                     path:(NSString *)path
                     body:(id)body
               completion:(LumiAPIRawCompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:method
                                                     path:path
                                                  baseURL:kNativeBaseURL
                                                     body:body
                                                needsAuth:YES];
    [self performRequest:request completion:^(NSDictionary *json, NSError *error) {
        if (error.code == 401 && self.refreshToken.length) {
            [self refreshIfNeededWithCompletion:^(BOOL ok) {
                if (!ok) {
                    completion(json, error);
                    return;
                }
                NSMutableURLRequest *retry = [self requestWithMethod:method
                                                               path:path
                                                            baseURL:kNativeBaseURL
                                                               body:body
                                                          needsAuth:YES];
                [self performRequest:retry completion:completion];
            }];
            return;
        }
        completion(json, error);
    }];
}

- (void)fetchProfileWithCompletion:(LumiAPIRawCompletion)completion {
    [self authorizedRequest:@"GET" path:@"/api/users/profile/" body:nil completion:completion];
}

- (void)fetchSessionsWithCompletion:(LumiAPIRawCompletion)completion {
    [self authorizedRequest:@"GET"
                       path:@"/api/chat/sessions/?pinned=false"
                       body:nil
                 completion:completion];
}

- (void)fetchMessagesForSession:(NSString *)sessionID
                     completion:(LumiAPIRawCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/api/chat/sessions/%@/messages/", sessionID];
    [self authorizedRequest:@"GET" path:path body:nil completion:completion];
}

- (void)createSessionWithDeviceContext:(NSDictionary *)deviceContext
                            completion:(LumiAPIRawCompletion)completion {
    [self authorizedRequest:@"POST"
                       path:@"/api/chat/sessions/"
                       body:@{@"platform": @"ios", @"device_context": deviceContext ?: @{}}
                 completion:completion];
}

- (void)sendMessage:(NSString *)text
          sessionID:(NSString *)sessionID
             turnID:(NSString *)turnID
             stepID:(NSString *)stepID
         completion:(LumiAPIRawCompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/api/chat/"
                                                  baseURL:kNativeBaseURL
                                                     body:@{@"message": text, @"session_id": sessionID}
                                                needsAuth:YES];
    if (turnID.length) {
        [request setValue:turnID forHTTPHeaderField:@"X-Chat-Turn-Id"];
    }
    if (stepID.length) {
        [request setValue:stepID forHTTPHeaderField:@"X-Chat-Step-Id"];
    }
    [self performRequest:request completion:completion];
}

#pragma mark - Public web API

- (void)fetchCatalogWithCompletion:(LumiAPIRawCompletion)completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                     path:@"/gallery/list?limit=50"
                                                  baseURL:kPublicBaseURL
                                                     body:nil
                                                needsAuth:NO];
    [self performRequest:request completion:completion];
}

- (void)fetchCharacterWithID:(NSString *)characterID
                  completion:(LumiAPIRawCompletion)completion {
    NSString *path = [NSString stringWithFormat:@"/public/characters/%@", characterID];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET"
                                                     path:path
                                                  baseURL:kPublicBaseURL
                                                     body:nil
                                                needsAuth:NO];
    [self performRequest:request completion:completion];
}

- (void)requestPasswordResetForEmail:(NSString *)email
                          completion:(void (^)(BOOL, NSString *))completion {
    NSMutableURLRequest *request = [self requestWithMethod:@"POST"
                                                     path:@"/auth/forgot-password"
                                                  baseURL:kPublicBaseURL
                                                     body:@{@"email": email}
                                                needsAuth:NO];
    [self performRequest:request completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(NO, error.localizedDescription);
            return;
        }
        completion(YES, @"Если аккаунт существует, письмо со ссылкой отправлено.");
    }];
}

@end
