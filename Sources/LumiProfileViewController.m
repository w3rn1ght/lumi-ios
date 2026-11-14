#import "LumiProfileViewController.h"
#import "LumiAPI.h"
#import "LumiDiagnostics.h"
#import "LumiCatalogStore.h"
#import "LumiImageLoader.h"
#import "LumiLoginViewController.h"
#import "LumiTheme.h"

@interface LumiProfileViewController ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *logoutButton;
@property (nonatomic, strong) UILabel *catalogLabel;
@property (nonatomic, strong) UIActivityIndicatorView *syncSpinner;
@end

@implementation LumiProfileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = @"Профиль";

    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.cornerRadius = 44.0;
    self.avatarView.backgroundColor = LumiSurfaceColor();
    self.avatarView.image = [UIImage imageNamed:@"LaunchLogo"];
    [self.view addSubview:self.avatarView];

    self.emailLabel = [[UILabel alloc] init];
    self.emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailLabel.textColor = LumiTextColor();
    self.emailLabel.font = LumiFont(18.0, UIFontWeightSemibold);
    self.emailLabel.textAlignment = NSTextAlignmentCenter;
    self.emailLabel.numberOfLines = 0;
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

    UIButton *refreshButton = [self buttonWithTitle:@"Обновить каталог" filled:NO];
    [refreshButton addTarget:self action:@selector(refreshCatalogTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:refreshButton];

    self.syncSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.syncSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.syncSpinner.color = LumiAccentColor();
    self.syncSpinner.hidesWhenStopped = YES;
    [self.view addSubview:self.syncSpinner];

    self.catalogLabel = [[UILabel alloc] init];
    self.catalogLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.catalogLabel.textColor = LumiMutedColor();
    self.catalogLabel.font = LumiFont(12.0, UIFontWeightRegular);
    self.catalogLabel.textAlignment = NSTextAlignmentCenter;
    self.catalogLabel.numberOfLines = 0;
    [self.view addSubview:self.catalogLabel];

    UIButton *aboutButton = [self buttonWithTitle:@"О приложении" filled:NO];
    [aboutButton addTarget:self action:@selector(aboutTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:aboutButton];

    UIButton *journalButton = [self buttonWithTitle:@"Журнал ошибок" filled:NO];
    [journalButton addTarget:self action:@selector(journalTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:journalButton];

    UILabel *version = [[UILabel alloc] init];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    version.text = @"Lumi 1.4.7 · нативный клиент";
    version.textColor = LumiMutedColor();
    version.font = LumiFont(12.0, UIFontWeightRegular);
    version.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:version];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.avatarView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:28.0],
        [self.avatarView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.avatarView.widthAnchor constraintEqualToConstant:88.0],
        [self.avatarView.heightAnchor constraintEqualToConstant:88.0],

        [self.emailLabel.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:14.0],
        [self.emailLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [self.emailLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.emailLabel.bottomAnchor constant:6.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.emailLabel.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.emailLabel.trailingAnchor],

        [self.loginButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:24.0],
        [self.loginButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loginButton.widthAnchor constraintEqualToConstant:240.0],
        [self.loginButton.heightAnchor constraintEqualToConstant:46.0],

        [self.logoutButton.topAnchor constraintEqualToAnchor:self.loginButton.bottomAnchor constant:10.0],
        [self.logoutButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.logoutButton.widthAnchor constraintEqualToConstant:240.0],
        [self.logoutButton.heightAnchor constraintEqualToConstant:46.0],

        [refreshButton.topAnchor constraintEqualToAnchor:self.logoutButton.bottomAnchor constant:10.0],
        [refreshButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [refreshButton.widthAnchor constraintEqualToConstant:240.0],
        [refreshButton.heightAnchor constraintEqualToConstant:46.0],

        [self.syncSpinner.centerYAnchor constraintEqualToAnchor:self.catalogLabel.centerYAnchor],
        [self.syncSpinner.trailingAnchor constraintEqualToAnchor:self.catalogLabel.leadingAnchor constant:-8.0],

        [self.catalogLabel.topAnchor constraintEqualToAnchor:refreshButton.bottomAnchor constant:14.0],
        [self.catalogLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [self.catalogLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],

        [aboutButton.topAnchor constraintEqualToAnchor:self.catalogLabel.bottomAnchor constant:10.0],
        [aboutButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [aboutButton.widthAnchor constraintEqualToConstant:240.0],
        [aboutButton.heightAnchor constraintEqualToConstant:46.0],

        [journalButton.topAnchor constraintEqualToAnchor:aboutButton.bottomAnchor constant:8.0],
        [journalButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [journalButton.widthAnchor constraintEqualToConstant:240.0],
        [journalButton.heightAnchor constraintEqualToConstant:40.0],

        [version.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16.0],
        [version.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [version.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authChanged)
                                                 name:LumiAuthDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogUpdated)
                                                 name:LumiCatalogDidUpdateNotification
                                               object:nil];

    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    [[LumiAPI sharedClient] refreshSessionWithCompletion:^(BOOL ok) {
        [self refresh];
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)authChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refresh];
    });
}

- (void)catalogUpdated {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshCatalogLabel];
    });
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
    LumiAPI *client = [LumiAPI sharedClient];
    if ([client isAuthenticated]) {
        LumiSessionUser *user = client.currentUser;
        self.emailLabel.text = [user displayName] ?: @"Аккаунт Lumi";
        self.statusLabel.text = @"Сессия Lumi активна — чаты синхронизируются с аккаунтом.";
        [[LumiImageLoader sharedLoader] loadURLString:user.avatarURL intoImageView:self.avatarView];
        self.loginButton.hidden = YES;
        self.logoutButton.hidden = NO;
    } else {
        self.emailLabel.text = @"Гость";
        self.statusLabel.text = @"Войдите, чтобы открыть чаты и продолжить переписки с аккаунта.";
        self.avatarView.image = [UIImage imageNamed:@"LaunchLogo"];
        self.loginButton.hidden = NO;
        self.logoutButton.hidden = YES;
    }
    [self refreshCatalogLabel];
}

- (void)refreshCatalogLabel {
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    if (store.isSyncing) {
        [self.syncSpinner startAnimating];
        self.catalogLabel.text = [store syncDetailedDescription];
        return;
    }
    [self.syncSpinner stopAnimating];
    if (!store.characters.count) {
        self.catalogLabel.text = @"Каталог ещё не загружен.";
        return;
    }
    self.catalogLabel.text = [NSString stringWithFormat:@"Каталог: %lu персонажей, %lu историй",
                              (unsigned long)store.characters.count, (unsigned long)store.stories.count];
}

- (void)loginTapped {
    LumiLoginViewController *login = [[LumiLoginViewController alloc] init];
    login.completion = ^{
        [self refresh];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:login];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)logoutTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Выйти из аккаунта?"
                                                                   message:@"Сессия будет удалена с этого устройства."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Выйти"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[LumiAPI sharedClient] logout];
        [[NSNotificationCenter defaultCenter] postNotificationName:LumiAuthDidChangeNotification object:nil];
        [self refresh];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshCatalogTapped {
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    if (store.isShowingSyncError) {
        [store retryFailedCharacterDetails];
    } else {
        [store forceRefresh];
    }
    [self refreshCatalogLabel];
}

- (void)journalTapped {
    UIViewController *controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = LumiBackgroundColor();
    controller.title = @"Журнал ошибок";

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.backgroundColor = LumiSurfaceColor();
    textView.textColor = LumiTextColor();
    textView.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0];
    textView.editable = NO;
    textView.alwaysBounceVertical = YES;
    textView.text = [LumiDiagnostics logContents];
    [controller.view addSubview:textView];

    UILayoutGuide *guide = controller.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8.0],
        [textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:10.0],
        [textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10.0],
        [textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-8.0],
    ]];

    controller.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissJournal)];
    controller.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Копировать"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyJournal)];

    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)dismissJournal {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)copyJournal {
    [UIPasteboard generalPasteboard].string = [LumiDiagnostics logContents];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Скопировано"
                                                                   message:@"Журнал в буфере обмена. Вставьте его в сообщение."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)aboutTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"О приложении"
                                                                   message:@"Нативный клиент Lumi для iOS 12.\n\nДанные: api.lumi.site и id.lumi.site.\nВход через OAuth-провайдеров (Google, Discord, Apple) — так же, как в официальном приложении Lumi, после чего сессия переносится в клиент через одноразовый токен.\nПароль не сохраняется на устройстве.\n\nНеофициальный клиент, не связан с Lumi AI."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
