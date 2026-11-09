#import "LumiAuthViewController.h"
#import "LumiAPIClient.h"
#import "LumiAppDelegate.h"
#import "LumiTheme.h"

@interface LumiAuthViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL registering;

@end

@implementation LumiAuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:content];

    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LaunchLogo"]];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Lumi";
    title.textColor = LumiTextColor();
    title.font = LumiFont(36.0, UIFontWeightBold);
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Нативный клиент для iOS 12";
    subtitle.textColor = LumiMutedColor();
    subtitle.font = LumiFont(14.0, UIFontWeightRegular);
    subtitle.textAlignment = NSTextAlignmentCenter;

    self.emailField = LumiTextField(@"Email");
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.emailField.textContentType = UITextContentTypeEmailAddress;
    self.emailField.returnKeyType = UIReturnKeyNext;

    self.passwordField = LumiTextField(@"Пароль");
    self.passwordField.secureTextEntry = YES;
    self.passwordField.textContentType = UITextContentTypePassword;
    self.passwordField.returnKeyType = UIReturnKeyGo;

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.primaryButton setTitle:@"Войти" forState:UIControlStateNormal];
    [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.primaryButton.titleLabel.font = LumiFont(17.0, UIFontWeightSemibold);
    self.primaryButton.backgroundColor = LumiAccentColor();
    self.primaryButton.layer.cornerRadius = 12.0;
    [self.primaryButton.heightAnchor constraintEqualToConstant:50.0].active = YES;
    [self.primaryButton addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];

    self.registerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.registerButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.registerButton setTitle:@"Создать аккаунт" forState:UIControlStateNormal];
    [self.registerButton setTitleColor:LumiTextColor() forState:UIControlStateNormal];
    self.registerButton.titleLabel.font = LumiFont(16.0, UIFontWeightMedium);
    self.registerButton.layer.cornerRadius = 12.0;
    self.registerButton.layer.borderWidth = 1.0;
    self.registerButton.layer.borderColor = LumiElevatedColor().CGColor;
    [self.registerButton.heightAnchor constraintEqualToConstant:50.0].active = YES;
    [self.registerButton addTarget:self action:@selector(toggleMode) forControlEvents:UIControlEventTouchUpInside];

    UIButton *forgotButton = [UIButton buttonWithType:UIButtonTypeSystem];
    forgotButton.translatesAutoresizingMaskIntoConstraints = NO;
    [forgotButton setTitle:@"Забыли пароль?" forState:UIControlStateNormal];
    [forgotButton setTitleColor:LumiMutedColor() forState:UIControlStateNormal];
    forgotButton.titleLabel.font = LumiFont(14.0, UIFontWeightRegular);
    [forgotButton addTarget:self action:@selector(forgotTapped) forControlEvents:UIControlEventTouchUpInside];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.textColor = [UIColor colorWithRed:0.98 green:0.44 blue:0.52 alpha:1.0];
    self.errorLabel.font = LumiFont(13.0, UIFontWeightRegular);
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        logo, title, subtitle, self.emailField, self.passwordField, self.primaryButton,
        self.registerButton, forgotButton, self.errorLabel
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    stack.alignment = UIStackViewAlignmentFill;
    [stack setCustomSpacing:24.0 afterView:subtitle];
    [stack setCustomSpacing:8.0 afterView:self.emailField];
    [stack setCustomSpacing:20.0 afterView:self.passwordField];
    [stack setCustomSpacing:10.0 afterView:self.primaryButton];
    [content addSubview:stack];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],

        [content.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [content.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],

        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor constant:40.0],
        [stack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:420.0],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-24.0],

        [logo.widthAnchor constraintEqualToConstant:96.0],
        [logo.heightAnchor constraintEqualToConstant:96.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    NSLayoutConstraint *width = [stack.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-48.0];
    width.priority = 999;
    width.active = YES;

    self.emailField.delegate = self;
    self.passwordField.delegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillChange:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = MAX(0.0, CGRectGetHeight(self.view.bounds) - [self.view convertRect:frame fromView:nil].origin.y);
    self.scrollView.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset;
}

- (void)toggleMode {
    self.registering = !self.registering;
    [self.primaryButton setTitle:(self.registering ? @"Зарегистрироваться" : @"Войти")
                        forState:UIControlStateNormal];
    [self.registerButton setTitle:(self.registering ? @"У меня уже есть аккаунт" : @"Создать аккаунт")
                         forState:UIControlStateNormal];
    self.errorLabel.hidden = YES;
}

- (void)primaryTapped {
    [self.view endEditing:YES];
    NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *password = self.passwordField.text;
    if (!email.length || !password.length) {
        [self showError:@"Введите email и пароль"];
        return;
    }
    [self setLoading:YES];
    self.errorLabel.hidden = YES;

    LumiAPIClient *client = [LumiAPIClient sharedClient];
    void (^finish)(id, NSError *) = ^(id result, NSError *error) {
        [self setLoading:NO];
        if (error) {
            [self showError:error.localizedDescription];
            return;
        }
        if (self.registering && ![client isAuthenticated]) {
            [self showAlert:@"Проверьте почту"
                    message:@"Аккаунт создан. Подтвердите email по ссылке из письма, затем войдите."];
            [self toggleMode];
            return;
        }
        void (^done)(void) = self.onSuccess;
        [self dismissViewControllerAnimated:YES completion:^{
            if (done) {
                done();
            }
        }];
    };

    if (self.registering) {
        [client registerWithEmail:email password:password completion:finish];
    } else {
        [client loginWithEmail:email password:password completion:finish];
    }
}

- (void)forgotTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Восстановление пароля"
                                                                   message:@"Введите email, и мы отправим ссылку для сброса пароля."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Email";
        textField.keyboardType = UIKeyboardTypeEmailAddress;
        textField.text = self.emailField.text;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отправить"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *email = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!email.length) {
            [self showError:@"Введите email"];
            return;
        }
        [self setLoading:YES];
        [[LumiAPIClient sharedClient] requestPasswordResetForEmail:email
                                                       completion:^(BOOL ok, NSString *message) {
            [self setLoading:NO];
            [self showAlert:(ok ? @"Готово" : @"Ошибка") message:message];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setLoading:(BOOL)loading {
    if (loading) {
        [self.spinner startAnimating];
        self.primaryButton.enabled = NO;
        self.primaryButton.alpha = 0.6;
    } else {
        [self.spinner stopAnimating];
        self.primaryButton.enabled = YES;
        self.primaryButton.alpha = 1.0;
    }
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [self primaryTapped];
    }
    return YES;
}

@end
