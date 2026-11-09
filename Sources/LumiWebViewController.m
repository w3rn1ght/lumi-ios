#import "LumiWebViewController.h"
#import "LumiApplication.h"

#import <WebKit/WebKit.h>

@protocol LumiWKUIDelegatePrivate <WKUIDelegate>
- (void)_webView:(WKWebView *)webView
    runOpenPanelWithParameters:(id)parameters
             initiatedByFrame:(WKFrameInfo *)frame
            completionHandler:(void (^)(NSArray<NSURL *> *URLs))completionHandler;
@end

static NSString *const kLumiHomeURLString = @"https://lumi.site/";
static void *LumiProgressObservationContext = &LumiProgressObservationContext;

@interface LumiWebViewController () <WKNavigationDelegate,
                                     LumiWKUIDelegatePrivate,
                                     UIGestureRecognizerDelegate,
                                     UIImagePickerControllerDelegate,
                                     UINavigationControllerDelegate,
                                     UIDocumentPickerDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *errorView;
@property (nonatomic, strong) UILabel *errorMessageLabel;
@property (nonatomic, strong) NSURL *lastFailedURL;
@property (nonatomic, copy) void (^uploadCompletionHandler)(NSArray<NSURL *> *URLs);

@end

@implementation LumiWebViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [self lumiBackgroundColor];
    [self setupWebView];
    [self setupProgressView];
    [self setupErrorView];
    [self setupGestures];
    [self loadHome];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMenuTrigger)
                                                 name:LumiApplicationDidShakeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.webView removeObserver:self
                      forKeyPath:@"estimatedProgress"
                         context:LumiProgressObservationContext];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (UIColor *)lumiBackgroundColor {
    return [UIColor colorWithRed:0.043 green:0.043 blue:0.071 alpha:1.0];
}

#pragma mark - Setup

- (void)setupWebView {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.preferences.javaScriptEnabled = YES;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    configuration.allowsInlineMediaPlayback = YES;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.allowsLinkPreview = YES;
    webView.customUserAgent = [self safariUserAgent];
    webView.opaque = NO;
    webView.backgroundColor = [self lumiBackgroundColor];
    webView.scrollView.backgroundColor = [self lumiBackgroundColor];
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    webView.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    webView.scrollView.scrollsToTop = YES;

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    refreshControl.tintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [refreshControl addTarget:self
                       action:@selector(refreshPulled:)
             forControlEvents:UIControlEventValueChanged];
    webView.scrollView.refreshControl = refreshControl;
    self.refreshControl = refreshControl;

    [self.view addSubview:webView];
    self.webView = webView;

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
    ]];

    [webView addObserver:self
              forKeyPath:@"estimatedProgress"
                 options:NSKeyValueObservingOptionNew
                 context:LumiProgressObservationContext];
}

- (NSString *)safariUserAgent {
    NSString *os = [[[UIDevice currentDevice] systemVersion] stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return [NSString stringWithFormat:@"Mozilla/5.0 (iPad; CPU OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1", os];
    }
    return [NSString stringWithFormat:@"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1", os];
}

- (void)setupProgressView {
    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    progressView.progressTintColor = [UIColor colorWithRed:0.64 green:0.36 blue:1.0 alpha:1.0];
    progressView.trackTintColor = [UIColor clearColor];
    progressView.hidden = YES;
    [self.view addSubview:progressView];
    self.progressView = progressView;

    [NSLayoutConstraint activateConstraints:@[
        [progressView.topAnchor constraintEqualToAnchor:self.webView.topAnchor],
        [progressView.leadingAnchor constraintEqualToAnchor:self.webView.leadingAnchor],
        [progressView.trailingAnchor constraintEqualToAnchor:self.webView.trailingAnchor],
        [progressView.heightAnchor constraintEqualToConstant:2.0],
    ]];
}

- (void)setupErrorView {
    UIView *errorView = [[UIView alloc] init];
    errorView.translatesAutoresizingMaskIntoConstraints = NO;
    errorView.backgroundColor = [self lumiBackgroundColor];
    errorView.hidden = YES;
    [self.view addSubview:errorView];
    self.errorView = errorView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Нет подключения";
    titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *messageLabel = [[UILabel alloc] init];
    messageLabel.text = @"Проверьте подключение к интернету и попробуйте снова.";
    messageLabel.font = [UIFont systemFontOfSize:15.0];
    messageLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.numberOfLines = 0;
    self.errorMessageLabel = messageLabel;

    UIButton *retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [retryButton setTitle:@"Повторить" forState:UIControlStateNormal];
    [retryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    retryButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    retryButton.backgroundColor = [UIColor colorWithRed:0.55 green:0.30 blue:0.95 alpha:1.0];
    retryButton.layer.cornerRadius = 12.0;
    retryButton.clipsToBounds = YES;
    [retryButton addTarget:self action:@selector(retryTapped:) forControlEvents:UIControlEventTouchUpInside];
    [retryButton.heightAnchor constraintEqualToConstant:46.0].active = YES;

    UIButton *safariButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [safariButton setTitle:@"Открыть в Safari" forState:UIControlStateNormal];
    [safariButton setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    safariButton.titleLabel.font = [UIFont systemFontOfSize:15.0];
    [safariButton addTarget:self action:@selector(openInSafari) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, messageLabel, retryButton, safariButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    stack.alignment = UIStackViewAlignmentFill;
    [errorView addSubview:stack];

    NSLayoutConstraint *widthConstraint = [stack.widthAnchor constraintEqualToAnchor:errorView.widthAnchor constant:-56.0];
    widthConstraint.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        [errorView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [errorView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [errorView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [errorView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:errorView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:errorView.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:420.0],
        widthConstraint,
    ]];
}

- (void)setupGestures {
    UITapGestureRecognizer *threeFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(handleMenuTrigger)];
    threeFingerTap.numberOfTouchesRequired = 3;
    threeFingerTap.cancelsTouchesInView = NO;
    threeFingerTap.delegate = self;
    [self.webView addGestureRecognizer:threeFingerTap];

    UISwipeGestureRecognizer *twoFingerSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                         action:@selector(handleMenuTrigger)];
    twoFingerSwipe.numberOfTouchesRequired = 2;
    twoFingerSwipe.direction = UISwipeGestureRecognizerDirectionDown;
    twoFingerSwipe.cancelsTouchesInView = NO;
    twoFingerSwipe.delegate = self;
    [self.webView addGestureRecognizer:twoFingerSwipe];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - Loading

- (void)loadHome {
    [self loadURL:[NSURL URLWithString:kLumiHomeURLString]];
}

- (void)loadURL:(NSURL *)url {
    if (!url) {
        return;
    }
    self.lastFailedURL = url;
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:30.0];
    [self.webView loadRequest:request];
}

- (void)retryTapped:(UIButton *)sender {
    self.errorView.hidden = YES;
    [self loadURL:self.lastFailedURL ?: [NSURL URLWithString:kLumiHomeURLString]];
}

- (void)refreshPulled:(UIRefreshControl *)sender {
    if (self.webView.URL) {
        [self.webView reload];
    } else {
        [self loadHome];
    }
}

- (void)reloadCurrentPage {
    if (self.webView.URL) {
        [self.webView reload];
    } else {
        [self loadHome];
    }
}

#pragma mark - Progress

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context != LumiProgressObservationContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    float progress = [change[NSKeyValueChangeNewKey] floatValue];
    [self.progressView setProgress:progress animated:YES];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.errorView.hidden = YES;
    self.progressView.hidden = NO;
    self.progressView.alpha = 1.0;
    [self.progressView setProgress:0.05 animated:NO];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.refreshControl endRefreshing];
    self.errorView.hidden = YES;
    self.lastFailedURL = webView.URL;
    [self.progressView setProgress:1.0 animated:YES];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (weakSelf.progressView.progress >= 0.999) {
            weakSelf.progressView.hidden = YES;
        }
    });
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    [self handleNavigationError:error];
}

- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    [self handleNavigationError:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self loadURL:webView.URL ?: [NSURL URLWithString:kLumiHomeURLString]];
}

- (void)handleNavigationError:(NSError *)error {
    [self.refreshControl endRefreshing];
    self.progressView.hidden = YES;

    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        return;
    }
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) {
        return;
    }

    self.lastFailedURL = self.webView.URL ?: self.lastFailedURL ?: [NSURL URLWithString:kLumiHomeURLString];
    self.errorMessageLabel.text = [self messageForError:error];
    self.errorView.hidden = NO;
}

- (NSString *)messageForError:(NSError *)error {
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
                return @"Проверьте подключение к интернету и попробуйте снова.";
            case NSURLErrorTimedOut:
                return @"Сервер Lumi не ответил вовремя. Попробуйте ещё раз.";
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorNetworkConnectionLost:
                return @"Не удалось подключиться к Lumi. Проверьте сеть.";
            case NSURLErrorSecureConnectionFailed:
                return @"Не удалось установить защищённое соединение.";
            default:
                break;
        }
    }
    return error.localizedDescription ?: @"Неизвестная ошибка.";
}

#pragma mark - Navigation policy

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (!url) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    // Subframes (captcha, payment widgets) are always allowed.
    if (navigationAction.targetFrame && !navigationAction.targetFrame.isMainFrame) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    // New windows are handled by createWebViewWithConfiguration:...
    if (!navigationAction.targetFrame) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        if ([self isTrustedURL:url]) {
            decisionHandler(WKNavigationActionPolicyAllow);
            return;
        }
        // Links to third-party sites are opened in Safari. Server redirects
        // (OAuth, payments) stay inside the web view so the flow keeps its cookies.
        if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
            [self openExternally:url];
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    if ([scheme isEqualToString:@"about"] ||
        [scheme isEqualToString:@"data"] ||
        [scheme isEqualToString:@"blob"] ||
        [scheme isEqualToString:@"javascript"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    [self openExternally:url];
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    if (!url) {
        return nil;
    }
    if ([self isTrustedURL:url]) {
        [webView loadRequest:navigationAction.request];
    } else {
        [self openExternally:url];
    }
    return nil;
}

- (BOOL)isTrustedURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (!host.length) {
        return NO;
    }

    NSArray<NSString *> *domains = @[@"lumi.site", @"lumi.ai"];
    for (NSString *domain in domains) {
        if ([host isEqualToString:domain] ||
            [host hasSuffix:[@"." stringByAppendingString:domain]]) {
            return YES;
        }
    }

    NSArray<NSString *> *exactHosts = @[
        @"accounts.google.com",
        @"accounts.youtube.com",
        @"appleid.apple.com",
        @"oauth.telegram.org",
        @"oauth.vk.com",
        @"id.vk.com",
        @"login.vk.com",
        @"yoomoney.ru",
        @"checkout.stripe.com",
        @"pay.google.com",
        @"challenges.cloudflare.com",
        @"hcaptcha.com",
    ];
    return [exactHosts containsObject:host];
}

- (void)openExternally:(NSURL *)url {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

#pragma mark - Menu

- (void)handleMenuTrigger {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showMenu];
    });
}

- (void)showMenu {
    if (self.presentedViewController || self.view.window == nil) {
        return;
    }

    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Lumi"
                                                                   message:[NSString stringWithFormat:@"Клиент lumi.site · v%@", version]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Обновить"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf reloadCurrentPage];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"На главную"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf loadHome];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Открыть в Safari"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf openInSafari];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Поделиться"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf shareCurrentPage];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Очистить кэш и cookies"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [weakSelf confirmClearWebsiteData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"О приложении"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf showAbout];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                    CGRectGetMidY(self.view.bounds),
                                                                    1.0, 1.0);
        sheet.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Actions

- (NSURL *)currentURL {
    return self.webView.URL ?: self.lastFailedURL ?: [NSURL URLWithString:kLumiHomeURLString];
}

- (void)openInSafari {
    NSURL *url = [self currentURL];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)shareCurrentPage {
    NSURL *url = [self currentURL];
    if (!url) {
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                                          applicationActivities:nil];
    activity.excludedActivityTypes = @[UIActivityTypeAddToReadingList];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                       CGRectGetMidY(self.view.bounds),
                                                                       1.0, 1.0);
        activity.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)confirmClearWebsiteData {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Очистить данные?"
                                                                   message:@"Будут удалены cookies, кэш и локальные данные сайта. Придётся войти заново."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Очистить"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [weakSelf clearWebsiteData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearWebsiteData {
    self.errorView.hidden = YES;
    self.progressView.hidden = NO;
    [self.progressView setProgress:0.1 animated:NO];

    __weak typeof(self) weakSelf = self;
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
                                            modifiedSince:[NSDate dateWithTimeIntervalSince1970:0]
                                        completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf loadHome];
        });
    }];
}

- (void)showAbout {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *message = [NSString stringWithFormat:
        @"Lumi для iOS %@\n\n"
        @"Неофициальный клиент lumi.site для устройств с джейлбрейком.\n"
        @"Не связан с Lumi AI.\n\n"
        @"Управление: три пальца по экрану, свайп двумя пальцами вниз или встряхивание.",
        version];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"О приложении"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - WKUIDelegate (JavaScript dialogs)

- (void)webView:(WKWebView *)webView
runJavaScriptAlertPanelWithMessage:(NSString *)message
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        completionHandler();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView
runJavaScriptConfirmPanelWithMessage:(NSString *)message
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(BOOL result))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        completionHandler(YES);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        completionHandler(NO);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView
runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
defaultText:(NSString *)defaultText
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(NSString *result))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:prompt
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = defaultText;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        completionHandler(alert.textFields.firstObject.text);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        completionHandler(nil);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - File uploads

- (void)_webView:(WKWebView *)webView
    runOpenPanelWithParameters:(id)parameters
             initiatedByFrame:(WKFrameInfo *)frame
            completionHandler:(void (^)(NSArray<NSURL *> *URLs))completionHandler {
    if (self.uploadCompletionHandler) {
        completionHandler(@[]);
        return;
    }
    self.uploadCompletionHandler = [completionHandler copy];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Загрузить файл"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Фото из галереи"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf presentPhotoPicker];
        });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Файлы"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf presentDocumentPicker];
        });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        [weakSelf finishUploadWithURLs:@[]];
    }]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                    CGRectGetMidY(self.view.bounds),
                                                                    1.0, 1.0);
        sheet.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentPhotoPicker {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self finishUploadWithURLs:@[]];
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image"];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentDocumentPicker {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"]
                                                               inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSData *data = image ? UIImageJPEGRepresentation(image, 0.92) : nil;
    if (!data) {
        [picker dismissViewControllerAnimated:YES completion:^{
            [self finishUploadWithURLs:@[]];
        }];
        return;
    }

    NSString *name = [NSString stringWithFormat:@"lumi-upload-%@.jpg", [[NSUUID UUID] UUIDString]];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    BOOL written = [data writeToURL:url options:NSDataWritingAtomic error:nil];

    [picker dismissViewControllerAnimated:YES completion:^{
        [self finishUploadWithURLs:(written ? @[url] : @[])];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:^{
        [self finishUploadWithURLs:@[]];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self copyPickedFiles:urls];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentAtURL:(NSURL *)url {
    [self copyPickedFiles:@[url]];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self finishUploadWithURLs:@[]];
}

- (void)copyPickedFiles:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSURL *> *localURLs = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSURL *sourceURL in urls) {
        if (!sourceURL) {
            continue;
        }
        BOOL scoped = [sourceURL startAccessingSecurityScopedResource];
        NSString *name = sourceURL.lastPathComponent.length ? sourceURL.lastPathComponent : @"upload";
        NSString *unique = [NSString stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString], name];
        NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:unique]];
        if ([fileManager copyItemAtURL:sourceURL toURL:destination error:nil]) {
            [localURLs addObject:destination];
        }
        if (scoped) {
            [sourceURL stopAccessingSecurityScopedResource];
        }
    }

    [self finishUploadWithURLs:localURLs];
}

- (void)finishUploadWithURLs:(NSArray<NSURL *> *)urls {
    void (^handler)(NSArray<NSURL *> *) = self.uploadCompletionHandler;
    self.uploadCompletionHandler = nil;
    if (!handler) {
        return;
    }
    NSArray<NSURL *> *safeURLs = urls ?: @[];
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(safeURLs);
    });
}

@end
