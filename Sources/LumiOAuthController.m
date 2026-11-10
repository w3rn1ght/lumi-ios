#import "LumiOAuthController.h"
#import "LumiAPI.h"
#import <AuthenticationServices/AuthenticationServices.h>

static NSString *const kCallbackScheme = @"ai.lumi.app";

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
@interface LumiOAuthController () <ASWebAuthenticationPresentationContextProviding>
#else
@interface LumiOAuthController ()
#endif
@property (nonatomic, strong, nullable) ASWebAuthenticationSession *session;
@property (nonatomic, weak, nullable) UIViewController *presenter;
@property (nonatomic, copy, nullable) void (^completion)(BOOL, NSError *);
@end

@implementation LumiOAuthController

- (void)dealloc {
    [self.session cancel];
}

- (NSString *)slugForProvider:(LumiOAuthProvider)provider {
    switch (provider) {
        case LumiOAuthProviderDiscord:
            return @"discord";
        case LumiOAuthProviderApple:
            return @"apple";
        case LumiOAuthProviderGoogle:
        default:
            return @"google";
    }
}

- (NSString *)titleForProvider:(LumiOAuthProvider)provider {
    switch (provider) {
        case LumiOAuthProviderDiscord:
            return @"Discord";
        case LumiOAuthProviderApple:
            return @"Apple";
        case LumiOAuthProviderGoogle:
        default:
            return @"Google";
    }
}

- (void)signInWithProvider:(LumiOAuthProvider)provider
                 presenter:(UIViewController *)presenter
                completion:(void (^)(BOOL, NSError *))completion {
    [self cancel];
    self.presenter = presenter;
    self.completion = completion;

    NSString *urlString = [NSString stringWithFormat:
        @"https://id.lumi.site/auth/oauth/%@?next=%%2Fhome&lang=ru&app=1",
        [self slugForProvider:provider]];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self finishWithSuccess:NO error:[self errorWithMessage:@"Не удалось открыть страницу входа"]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    ASWebAuthenticationSession *session =
        [[ASWebAuthenticationSession alloc] initWithURL:url
                                      callbackURLScheme:kCallbackScheme
                                      completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleCallbackURL:callbackURL error:error provider:provider];
        });
    }];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        session.presentationContextProvider = self;
    }
#endif
    self.session = session;
    if (![session start]) {
        [self finishWithSuccess:NO error:[self errorWithMessage:@"Не удалось открыть окно входа"]];
    }
}

- (void)cancel {
    // Keep the completion handler: cancelling the session reports a cancellation error.
    [self.session cancel];
    self.session = nil;
}

#pragma mark - Callback

- (void)handleCallbackURL:(NSURL *)callbackURL
                    error:(NSError *)error
                 provider:(LumiOAuthProvider)provider {
    if (error) {
        self.session = nil;
        if (error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin) {
            [self finishWithSuccess:NO error:nil];
            return;
        }
        [self finishWithSuccess:NO error:[self errorWithMessage:error.localizedDescription]];
        return;
    }
    if (!callbackURL) {
        [self finishWithSuccess:NO error:[self errorWithMessage:@"Вход отменён"]];
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:callbackURL resolvingAgainstBaseURL:NO];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name && item.value) {
            params[item.name] = item.value;
        }
    }
    NSLog(@"[Lumi] oauth callback: %@", params);

    NSString *providerError = params[@"error"];
    if (providerError.length) {
        [self finishWithSuccess:NO error:[self errorWithMessage:[self messageForProviderError:providerError]]];
        return;
    }
    NSString *token = params[@"token"];
    if (!token.length) {
        [self finishWithSuccess:NO error:[self errorWithMessage:@"Сервер не вернул токен входа"]];
        return;
    }
    [self exchangeToken:token provider:provider];
}

- (NSString *)messageForProviderError:(NSString *)code {
    if ([code isEqualToString:@"oauth_state_invalid"]) {
        return @"Ссылка входа истекла. Попробуйте снова.";
    }
    if ([code isEqualToString:@"oauth_missing_params"]) {
        return @"Не удалось войти. Попробуйте снова.";
    }
    if ([code containsString:@"email_not_verified"]) {
        return @"Подтвердите email в аккаунте провайдера и попробуйте снова.";
    }
    if ([code containsString:@"email_missing"]) {
        return @"К аккаунту не привязан email.";
    }
    if ([code containsString:@"not_configured"]) {
        return @"Этот способ входа пока не настроен на сервере Lumi.";
    }
    return [NSString stringWithFormat:@"Не удалось войти (%@)", code];
}

#pragma mark - Token exchange

- (void)exchangeToken:(NSString *)token provider:(LumiOAuthProvider)provider {
    LumiAPI *api = [LumiAPI sharedClient];
    [api exchangeAppToken:token completion:^(NSError *error) {
        if (error) {
            [self finishWithSuccess:NO error:error];
            return;
        }
        [api refreshSessionWithCompletion:^(BOOL ok) {
            if (ok) {
                [self finishWithSuccess:YES error:nil];
                return;
            }
            [self finishWithSuccess:NO error:[self errorWithMessage:@"Сессия Lumi не подтвердилась. Попробуйте войти ещё раз."]];
        }];
    }];
}

#pragma mark - Helpers

- (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:LumiAPIErrorDomain
                               code:401
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Не удалось войти"}];
}

- (void)finishWithSuccess:(BOOL)success error:(NSError *)error {
    self.session = nil;
    void (^completion)(BOOL, NSError *) = self.completion;
    self.completion = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(success, error);
        }
    });
}

#pragma mark - ASWebAuthenticationPresentationContextProviding

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    UIWindow *window = self.presenter.view.window;
    if (window) {
        return window;
    }
    return [UIApplication sharedApplication].keyWindow;
}
#endif

@end
