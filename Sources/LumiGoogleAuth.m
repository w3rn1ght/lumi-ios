#import "LumiGoogleAuth.h"

#import <CommonCrypto/CommonDigest.h>
#import <SafariServices/SafariServices.h>
#import <stdlib.h>

NSString *const LumiGoogleAuthErrorDomain = @"com.w3rn1ght.lumi.google";

static NSString *const kGoogleClientID =
    @"1032314291008-enums0tts15iutfse3tl0j2jdr8npi75.apps.googleusercontent.com";
static NSString *const kGoogleServerClientID =
    @"1032314291008-hhv47buaasu94qb10fa63rp49nkvg9ba.apps.googleusercontent.com";
static NSString *const kGoogleCallbackScheme =
    @"com.googleusercontent.apps.1032314291008-enums0tts15iutfse3tl0j2jdr8npi75";
static NSString *const kGoogleRedirectURI =
    @"com.googleusercontent.apps.1032314291008-enums0tts15iutfse3tl0j2jdr8npi75:/oauth2callback";
static NSString *const kGoogleAuthorizationURL = @"https://accounts.google.com/o/oauth2/v2/auth";
static NSString *const kGoogleTokenURL = @"https://oauth2.googleapis.com/token";

static NSString *LumiFormEncode(NSString *value) {
    static NSCharacterSet *allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *LumiBase64URLEncode(NSData *data) {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

static NSData * _Nullable LumiBase64URLDecode(NSString *string) {
    NSMutableString *base64 = [string mutableCopy];
    [base64 replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
    while (base64.length % 4 != 0) {
        [base64 appendString:@"="];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

static NSString *LumiRandomURLSafeString(NSUInteger byteCount) {
    uint8_t bytes[byteCount];
    arc4random_buf(bytes, byteCount);
    return LumiBase64URLEncode([NSData dataWithBytes:bytes length:byteCount]);
}

@interface LumiGoogleAuth ()
@property (nonatomic, strong, nullable) SFAuthenticationSession *session;
@property (nonatomic, copy, nullable) NSString *flowID;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *codeVerifier;
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation LumiGoogleAuth

+ (instancetype)sharedAuth {
    static LumiGoogleAuth *auth;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        auth = [[LumiGoogleAuth alloc] init];
    });
    return auth;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 30.0;
        configuration.timeoutIntervalForResource = 60.0;
        _urlSession = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (NSError *)errorWithMessage:(NSString *)message code:(LumiGoogleAuthErrorCode)code {
    return [NSError errorWithDomain:LumiGoogleAuthErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSError *)cancelledError {
    return [self errorWithMessage:@"Вход через Google отменён." code:LumiGoogleAuthErrorCancelled];
}

- (void)signInFromViewController:(UIViewController *)presenter
                      completion:(LumiGoogleAuthCompletion)completion {
    (void)presenter;
    if (self.session) {
        [self.session cancel];
        self.session = nil;
    }

    NSString *flowID = [[NSUUID UUID] UUIDString];
    self.flowID = flowID;

    NSString *verifier = LumiRandomURLSafeString(32);
    NSData *verifierData = [verifier dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(verifierData.bytes, (CC_LONG)verifierData.length, digest);
    NSString *challenge = LumiBase64URLEncode([NSData dataWithBytes:digest length:sizeof(digest)]);

    NSString *state = LumiRandomURLSafeString(16);
    self.codeVerifier = verifier;
    self.state = state;

    NSDictionary<NSString *, NSString *> *parameters = @{
        @"client_id": kGoogleClientID,
        @"redirect_uri": kGoogleRedirectURI,
        @"response_type": @"code",
        @"scope": @"openid email profile",
        @"code_challenge": challenge,
        @"code_challenge_method": @"S256",
        @"state": state,
        @"audience": kGoogleServerClientID,
        @"include_granted_scopes": @"true",
        @"prompt": @"select_account",
    };

    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSString *key in parameters) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", LumiFormEncode(key), LumiFormEncode(parameters[key])]];
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:kGoogleAuthorizationURL];
    components.percentEncodedQuery = [pairs componentsJoinedByString:@"&"];
    NSURL *authorizationURL = components.URL;
    if (!authorizationURL) {
        completion(nil, nil, [self errorWithMessage:@"Не удалось открыть страницу Google." code:LumiGoogleAuthErrorFailed]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    SFAuthenticationSession *session = [[SFAuthenticationSession alloc] initWithURL:authorizationURL
                                                                 callbackURLScheme:kGoogleCallbackScheme
                                                                 completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.flowID isEqualToString:flowID]) {
            return;
        }
        strongSelf.session = nil;
        strongSelf.flowID = nil;

        if (error) {
            if ([error.domain isEqualToString:SFAuthenticationErrorDomain] &&
                error.code == SFAuthenticationErrorCanceledLogin) {
                completion(nil, nil, [strongSelf cancelledError]);
            } else {
                completion(nil, nil, [strongSelf errorWithMessage:error.localizedDescription
                                                            code:LumiGoogleAuthErrorFailed]);
            }
            return;
        }

        [strongSelf handleCallbackURL:callbackURL completion:completion];
    }];

    self.session = session;
    if (![session start]) {
        self.session = nil;
        self.flowID = nil;
        completion(nil, nil, [self errorWithMessage:@"Не удалось открыть окно входа Google." code:LumiGoogleAuthErrorFailed]);
    }
}

- (void)cancel {
    self.flowID = nil;
    [self.session cancel];
    self.session = nil;
}

- (void)handleCallbackURL:(NSURL *)callbackURL completion:(LumiGoogleAuthCompletion)completion {
    if (!callbackURL) {
        completion(nil, nil, [self errorWithMessage:@"Google не вернул результат входа." code:LumiGoogleAuthErrorFailed]);
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:callbackURL resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name && item.value) {
            query[item.name] = item.value;
        }
    }

    NSString *errorCode = query[@"error"];
    if (errorCode.length) {
        if ([errorCode isEqualToString:@"access_denied"]) {
            completion(nil, nil, [self cancelledError]);
        } else {
            NSString *detail = query[@"error_description"] ?: errorCode;
            completion(nil, nil, [self errorWithMessage:detail code:LumiGoogleAuthErrorFailed]);
        }
        return;
    }

    NSString *returnedState = query[@"state"];
    if (!self.state.length || ![returnedState isEqualToString:self.state]) {
        completion(nil, nil, [self errorWithMessage:@"Проверка состояния входа Google не удалась." code:LumiGoogleAuthErrorFailed]);
        return;
    }

    NSString *code = query[@"code"];
    if (!code.length) {
        completion(nil, nil, [self errorWithMessage:@"Google не вернул код авторизации." code:LumiGoogleAuthErrorFailed]);
        return;
    }

    [self exchangeAuthorizationCode:code completion:completion];
}

- (void)exchangeAuthorizationCode:(NSString *)code completion:(LumiGoogleAuthCompletion)completion {
    NSDictionary<NSString *, NSString *> *parameters = @{
        @"client_id": kGoogleClientID,
        @"code": code,
        @"code_verifier": self.codeVerifier ?: @"",
        @"grant_type": @"authorization_code",
        @"redirect_uri": kGoogleRedirectURI,
        @"audience": kGoogleServerClientID,
    };
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSString *key in parameters) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", LumiFormEncode(key), LumiFormEncode(parameters[key])]];
    }
    NSData *body = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kGoogleTokenURL]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"Lumi/1.2.0 (iOS)" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, nil, [strongSelf errorWithMessage:error.localizedDescription
                                                            code:LumiGoogleAuthErrorFailed]);
                return;
            }
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if (http.statusCode < 200 || http.statusCode >= 300 || ![json isKindOfClass:[NSDictionary class]]) {
                NSString *message = @"Google отклонил вход.";
                if ([json isKindOfClass:[NSDictionary class]]) {
                    NSString *detail = json[@"error_description"] ?: json[@"error"];
                    if ([detail isKindOfClass:[NSString class]] && detail.length) {
                        message = detail;
                    }
                }
                completion(nil, nil, [strongSelf errorWithMessage:message code:LumiGoogleAuthErrorFailed]);
                return;
            }

            NSString *idToken = json[@"id_token"];
            if (![idToken isKindOfClass:[NSString class]] || !idToken.length) {
                completion(nil, nil, [strongSelf errorWithMessage:@"Google не вернул ID token."
                                                            code:LumiGoogleAuthErrorFailed]);
                return;
            }

            completion(idToken, [strongSelf emailFromIDToken:idToken], nil);
        });
    }];
    [task resume];
}

- (nullable NSString *)emailFromIDToken:(NSString *)idToken {
    NSArray<NSString *> *parts = [idToken componentsSeparatedByString:@"."];
    if (parts.count < 2) {
        return nil;
    }
    NSData *payload = LumiBase64URLDecode(parts[1]);
    if (!payload.length) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *email = json[@"email"];
    return [email isKindOfClass:[NSString class]] ? email : nil;
}

@end
