#import "LumiLoginViewController.h"
#import "LumiAPI.h"
#import "LumiTheme.h"
#import "LumiWebAuthViewController.h"

@interface LumiLoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
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

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    stack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:stack];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"С возвращением";
    title.font = LumiFont(28.0, UIFontWeightBold);
    title.textColor = LumiTextColor();
    title.numberOfLines = 0;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"Войдите, чтобы чаты синхронизировались с вашим аккаунтом Lumi.";
    subtitle.font = LumiFont(14.0, UIFontWeightRegular);
    subtitle.textColor = LumiMutedColor();
    subtitle.numberOfLines = 0;

    UIButton *browserButton = [self primaryButtonWithTitle:@"Войти через браузер"];
    [browserButton addTarget:self action:@selector(openWebLogin) forControlEvents:UIControlEventTouchUpInside];

    UILabel *browserHint = [[UILabel alloc] init];
    browserHint.text = @"Google, Discord, Apple, капча и сброс пароля открываются во встроенном браузере.";
    browserHint.font = LumiFont(12.0, UIFontWeightRegular);
    browserHint.textColor = LumiMutedColor();
    browserHint.numberOfLines = 0;

    UILabel *divider = [[UILabel alloc] init];
    divider.text = @"или по email";
    divider.font = LumiFont(12.0, UIFontWeightMedium);
    divider.textColor = LumiMutedColor();
    divider.textAlignment = NSTextAlignmentCenter;

    self.emailField = LumiTextField(@"Email");
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.emailField.textContentType = UITextContentTypeUsername;
    self.emailField.returnKeyType = UIReturnKeyNext;
    self.emailField.delegate = self;

    self.passwordField = LumiTextField(@"Пароль");
    self.passwordField.secureTextEntry = YES;
    self.passwordField.textContentType = UITextContentTypePassword;
    self.passwordField.returnKeyType = UIReturnKeyGo;
    self.passwordField.delegate = self;

    self.loginButton = [self primaryButtonWithTitle:@"Войти"];
    [self.loginButton addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = LumiFont(12.0, UIFontWeightRegular);
    self.errorLabel.textColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.45 alpha:1.0];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;

    UIButton *forgot = [self linkButtonWithTitle:@"Забыли пароль?"];
    [forgot addTarget:self action:@selector(openForgotPassword) forControlEvents:UIControlEventTouchUpInside];

    UIButton *registerButton = [self linkButtonWithTitle:@"Создать аккаунт"];
    [registerButton addTarget:self action:@selector(openRegister) forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = LumiMutedColor();

    [stack addArrangedSubview:title];
    [stack addArrangedSubview:subtitle];
    [stack addArrangedSubview:browserButton];
    [stack addArrangedSubview:browserHint];
    [stack addArrangedSubview:divider];
    [stack addArrangedSubview:self.emailField];
    [stack addArrangedSubview:self.passwordField];
    [stack addArrangedSubview:self.errorLabel];
    [stack addArrangedSubview:self.loginButton];
    [stack addArrangedSubview:self.spinner];
    [stack addArrangedSubview:forgot];
    [stack addArrangedSubview:registerButton];
    [stack setCustomSpacing:24.0 afterView:subtitle];
    [stack setCustomSpacing:6.0 afterView:divider];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:24.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24.0],
        [stack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-40.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(webAuthCompleted)
                                                 name:LumiWebAuthDidCompleteNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI helpers

- (UIButton *)primaryButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = LumiAccentColor();
    button.layer.cornerRadius = 12.0;
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

- (UIButton *)linkButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = LumiFont(14.0, UIFontWeightMedium);
    [button setTitleColor:LumiAccentColor() forState:UIControlStateNormal];
    [button.heightAnchor constraintEqualToConstant:30.0].active = YES;
    return button;
}

#pragma mark - Actions

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openWebLogin {
    [self presentWebPath:@"/login?next=%2Fhome"];
}

- (void)openRegister {
    [self presentWebPath:@"/register?next=%2Fhome"];
}

- (void)openForgotPassword {
    [self presentWebPath:@"/forgot-password"];
}

- (void)presentWebPath:(NSString *)path {
    LumiWebAuthViewController *controller = [[LumiWebAuthViewController alloc] initWithPath:path];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)webAuthCompleted {
    [self finishSuccessfully];
}

- (void)loginTapped {
    [self.view endEditing:YES];
    NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = self.passwordField.text ?: @"";
    if (!email.length || !password.length) {
        [self showError:@"Введите email и пароль."];
        return;
    }
    [self setLoading:YES];
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] loginWithEmail:email password:password completion:^(id result, NSError *error) {
        [weakSelf setLoading:NO];
        if (error) {
            [weakSelf showError:error.localizedDescription];
            return;
        }
        [weakSelf finishSuccessfully];
    }];
}

- (void)setLoading:(BOOL)loading {
    self.loginButton.enabled = !loading;
    self.loginButton.alpha = loading ? 0.6 : 1.0;
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

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [self loginTapped];
    }
    return YES;
}

@end
