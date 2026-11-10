#import "LumiWebAuthViewController.h"
#import "LumiAPI.h"
#import "LumiTheme.h"
#import <WebKit/WebKit.h>

NSString *const LumiWebAuthDidCompleteNotification = @"LumiWebAuthDidCompleteNotification";

static NSString *const kSafariUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 12_5 like Mac OS X) AppleWebKit/605.1.15 "
    @"(KHTML, like Gecko) Version/12.1 Mobile/15E148 Safari/604.1";

@interface LumiWebAuthViewController () <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, assign) BOOL finished;
@end

@implementation LumiWebAuthViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _path = [path copy] ?: @"/login";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = @"Вход в Lumi";

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:@"Закрыть"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem = close;
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Готово"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(doneTapped)];
    self.navigationItem.rightBarButtonItem = done;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.allowsInlineMediaPlayback = YES;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = LumiBackgroundColor();
    self.webView.scrollView.backgroundColor = LumiBackgroundColor();
    self.webView.customUserAgent = kSafariUserAgent;
    [self.view addSubview:self.webView];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.color = LumiAccentColor();
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.font = LumiFont(12.0, UIFontWeightRegular);
    self.hintLabel.textColor = LumiMutedColor();
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.text = @"Войдите удобным способом. После входа нажмите «Готово».";
    [self.view addSubview:self.hintLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.hintLabel.topAnchor constant:-6.0],

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],

        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    NSString *urlString = [@"https://lumi.site" stringByAppendingString:self.path];
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];
}

#pragma mark - Actions

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped {
    [self captureCookiesAndFinish];
}

#pragma mark - Cookie capture

- (void)captureCookiesAndFinish {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self.activityIndicator startAnimating];
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    __weak typeof(self) weakSelf = self;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSMutableArray<NSHTTPCookie *> *lumiCookies = [NSMutableArray array];
        for (NSHTTPCookie *cookie in cookies) {
            if ([cookie.domain containsString:@"lumi.site"]) {
                [lumiCookies addObject:cookie];
            }
        }
        NSLog(@"[Lumi] web auth captured %lu cookies", (unsigned long)lumiCookies.count);
        [[LumiAPI sharedClient] storeCookies:lumiCookies];
        [[LumiAPI sharedClient] refreshSessionWithCompletion:^(BOOL ok) {
            [weakSelf.activityIndicator stopAnimating];
            if (ok) {
                [weakSelf dismissViewControllerAnimated:YES completion:^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:LumiWebAuthDidCompleteNotification object:nil];
                }];
                return;
            }
            weakSelf.finished = NO;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Вход не завершён"
                                                                           message:@"Не удалось найти сессию Lumi. Войдите на сайте и нажмите «Готово» ещё раз."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }];
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.activityIndicator startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.activityIndicator stopAnimating];
    NSString *urlString = webView.URL.absoluteString ?: @"";
    NSLog(@"[Lumi] web auth navigation: %@", urlString);
    BOOL isLumi = [urlString containsString:@"lumi.site"];
    BOOL onLogin = [urlString containsString:@"/login"] || [urlString containsString:@"/register"] ||
                   [urlString containsString:@"accounts.google.com"] || [urlString containsString:@"yandex"];
    if (isLumi && !onLogin) {
        [self captureCookiesAndFinish];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.activityIndicator stopAnimating];
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

@end
