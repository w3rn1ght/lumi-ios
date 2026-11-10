#import "LumiLoginViewController.h"
#import "LumiAPI.h"
#import "LumiOAuthController.h"
#import "LumiTheme.h"

@interface LumiLoginViewController ()
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) LumiOAuthController *oauth;
@property (nonatomic, strong) NSArray<UIButton *> *providerButtons;
@end

@implementation LumiLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = @"Вход";

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:@"Закрыть"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem = close;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    stack.alignment = UIStackViewAlignmentFill;
    [scrollView addSubview:stack];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"С возвращением";
    title.font = LumiFont(28.0, UIFontWeightBold);
    title.textColor = LumiTextColor();
    title.numberOfLines = 0;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"Войдите, чтобы чаты и переписки синхронизировались с вашим аккаунтом Lumi.";
    subtitle.font = LumiFont(14.0, UIFontWeightRegular);
    subtitle.textColor = LumiMutedColor();
    subtitle.numberOfLines = 0;

    UIButton *google = [self buttonWithTitle:@"Продолжить с Google" filled:YES];
    google.tag = LumiOAuthProviderGoogle;
    [google addTarget:self action:@selector(providerTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *discord = [self buttonWithTitle:@"Продолжить с Discord" filled:NO];
    discord.tag = LumiOAuthProviderDiscord;
    [discord addTarget:self action:@selector(providerTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *apple = [self buttonWithTitle:@"Продолжить с Apple" filled:NO];
    apple.tag = LumiOAuthProviderApple;
    [apple addTarget:self action:@selector(providerTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.providerButtons = @[google, discord, apple];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = LumiFont(12.0, UIFontWeightRegular);
    self.errorLabel.textColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.45 alpha:1.0];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = LumiMutedColor();

    UILabel *note = [[UILabel alloc] init];
    note.text = @"Вход по email и паролю на сайте Lumi защищён капчей, поэтому в приложении доступен только вход через провайдеров. Регистрация и сброс пароля — на сайте.";
    note.font = LumiFont(12.0, UIFontWeightRegular);
    note.textColor = LumiMutedColor();
    note.numberOfLines = 0;

    UIButton *siteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [siteButton setTitle:@"Открыть сайт Lumi" forState:UIControlStateNormal];
    siteButton.titleLabel.font = LumiFont(14.0, UIFontWeightMedium);
    [siteButton setTitleColor:LumiAccentColor() forState:UIControlStateNormal];
    [siteButton.heightAnchor constraintEqualToConstant:30.0].active = YES;
    [siteButton addTarget:self action:@selector(openSite) forControlEvents:UIControlEventTouchUpInside];

    [stack addArrangedSubview:title];
    [stack addArrangedSubview:subtitle];
    [stack addArrangedSubview:google];
    [stack addArrangedSubview:discord];
    [stack addArrangedSubview:apple];
    [stack addArrangedSubview:self.errorLabel];
    [stack addArrangedSubview:self.spinner];
    [stack addArrangedSubview:note];
    [stack addArrangedSubview:siteButton];
    [stack setCustomSpacing:24.0 afterView:subtitle];
    [stack setCustomSpacing:20.0 afterView:apple];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:24.0],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-24.0],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-40.0],
    ]];

    self.oauth = [[LumiOAuthController alloc] init];
}

- (UIButton *)buttonWithTitle:(NSString *)title filled:(BOOL)filled {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    [button setTitleColor:(filled ? [UIColor whiteColor] : LumiTextColor()) forState:UIControlStateNormal];
    button.backgroundColor = filled ? LumiAccentColor() : LumiSurfaceColor();
    button.layer.cornerRadius = 12.0;
    if (!filled) {
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = LumiElevatedColor().CGColor;
    }
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

#pragma mark - Actions

- (void)closeTapped {
    [self.oauth cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)providerTapped:(UIButton *)sender {
    LumiOAuthProvider provider = (LumiOAuthProvider)sender.tag;
    [self setLoading:YES];
    self.errorLabel.hidden = YES;
    __weak typeof(self) weakSelf = self;
    [self.oauth signInWithProvider:provider presenter:self completion:^(BOOL ok, NSError *error) {
        [weakSelf setLoading:NO];
        if (ok) {
            [weakSelf finishSuccessfully];
            return;
        }
        if (error) {
            [weakSelf showError:error.localizedDescription];
        }
    }];
}

- (void)openSite {
    NSURL *url = [NSURL URLWithString:@"https://lumi.site/login"];
    if (url) {
        [[UIApplication sharedApplication] openURL:url];
    }
}

- (void)setLoading:(BOOL)loading {
    for (UIButton *button in self.providerButtons) {
        button.enabled = !loading;
        button.alpha = loading ? 0.6 : 1.0;
    }
    if (loading) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
    }
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
}

- (void)finishSuccessfully {
    [[NSNotificationCenter defaultCenter] postNotificationName:LumiAuthDidChangeNotification object:nil];
    void (^completion)(void) = self.completion;
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) {
            completion();
        }
    }];
}

@end
