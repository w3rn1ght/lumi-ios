#import "LumiProfileViewController.h"
#import "LumiAPIClient.h"
#import "LumiAuthViewController.h"
#import "LumiTheme.h"

@interface LumiProfileViewController ()
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *logoutButton;
@end

@implementation LumiProfileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();

    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LaunchLogo"]];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:logo];

    self.emailLabel = [[UILabel alloc] init];
    self.emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailLabel.textColor = LumiTextColor();
    self.emailLabel.font = LumiFont(18.0, UIFontWeightSemibold);
    self.emailLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.emailLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = LumiMutedColor();
    self.statusLabel.font = LumiFont(13.0, UIFontWeightRegular);
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [self.view addSubview:self.statusLabel];

    self.loginButton = [self buttonWithTitle:@"Войти" filled:YES];
    [self.loginButton addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.loginButton];

    self.logoutButton = [self buttonWithTitle:@"Выйти" filled:NO];
    [self.logoutButton addTarget:self action:@selector(logoutTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.logoutButton];

    UIButton *aboutButton = [self buttonWithTitle:@"О приложении" filled:NO];
    [aboutButton addTarget:self action:@selector(aboutTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:aboutButton];

    UILabel *version = [[UILabel alloc] init];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.text = @"Lumi 1.1.0 · нативный клиент";
    version.textColor = LumiMutedColor();
    version.font = LumiFont(12.0, UIFontWeightRegular);
    version.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:version];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [logo.topAnchor constraintEqualToAnchor:guide.topAnchor constant:36.0],
        [logo.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [logo.widthAnchor constraintEqualToConstant:88.0],
        [logo.heightAnchor constraintEqualToConstant:88.0],

        [self.emailLabel.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:14.0],
        [self.emailLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [self.emailLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.emailLabel.bottomAnchor constant:6.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.emailLabel.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.emailLabel.trailingAnchor],

        [self.loginButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:24.0],
        [self.loginButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loginButton.widthAnchor constraintEqualToConstant:220.0],
        [self.loginButton.heightAnchor constraintEqualToConstant:46.0],

        [self.logoutButton.topAnchor constraintEqualToAnchor:self.loginButton.bottomAnchor constant:10.0],
        [self.logoutButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.logoutButton.widthAnchor constraintEqualToConstant:220.0],
        [self.logoutButton.heightAnchor constraintEqualToConstant:46.0],

        [aboutButton.topAnchor constraintEqualToAnchor:self.logoutButton.bottomAnchor constant:10.0],
        [aboutButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [aboutButton.widthAnchor constraintEqualToConstant:220.0],
        [aboutButton.heightAnchor constraintEqualToConstant:46.0],

        [version.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16.0],
        [version.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [version.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],
    ]];

    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (UIButton *)buttonWithTitle:(NSString *)title filled:(BOOL)filled {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:(filled ? [UIColor whiteColor] : LumiTextColor()) forState:UIControlStateNormal];
    button.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    button.backgroundColor = filled ? LumiAccentColor() : LumiSurfaceColor();
    button.layer.cornerRadius = 12.0;
    if (!filled) {
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = LumiElevatedColor().CGColor;
    }
    return button;
}

- (void)refresh {
    LumiAPIClient *client = [LumiAPIClient sharedClient];
    if ([client isAuthenticated]) {
        self.emailLabel.text = client.userEmail ?: @"Аккаунт Lumi";
        self.statusLabel.text = @"Вы вошли в аккаунт";
        self.loginButton.hidden = YES;
        self.logoutButton.hidden = NO;
    } else {
        self.emailLabel.text = @"Гость";
        self.statusLabel.text = @"Войдите, чтобы открыть чаты и историю";
        self.loginButton.hidden = NO;
        self.logoutButton.hidden = YES;
    }
}

- (void)loginTapped {
    LumiAuthViewController *auth = [[LumiAuthViewController alloc] init];
    auth.onSuccess = ^{
        [self refresh];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:auth];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    auth.title = @"Вход";
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)logoutTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Выйти из аккаунта?"
                                                                   message:@"Токены будут удалены с этого устройства."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Выйти"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[LumiAPIClient sharedClient] logout];
        [self refresh];
        self.tabBarController.selectedIndex = 0;
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)aboutTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"О приложении"
                                                                   message:@"Нативный клиент Lumi для iOS 12.\n\nДанные: lumi-api.nexoragroup.dev и api.lumi.site.\nПароль не сохраняется на устройстве, хранятся только токены.\n\nНеофициальный клиент, не связан с Lumi AI."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
