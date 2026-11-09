#import "LumiCharacterViewController.h"
#import "LumiAPIClient.h"
#import "LumiAuthViewController.h"
#import "LumiChatViewController.h"
#import "LumiImageLoader.h"
#import "LumiTheme.h"

@interface LumiCharacterViewController ()
@property (nonatomic, copy) NSString *characterID;
@property (nonatomic, copy) NSString *characterName;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *taglineLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UILabel *backstoryLabel;
@property (nonatomic, strong) UILabel *firstMessageLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation LumiCharacterViewController

- (instancetype)initWithCharacterID:(NSString *)characterID
                               name:(NSString *)name
                             avatar:(NSString *)avatar {
    self = [super init];
    if (self) {
        _characterID = [characterID copy];
        _characterName = [name copy];
        _avatarURL = [avatar copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = self.characterName;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.cornerRadius = 60.0;
    self.avatarView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    [self.scrollView addSubview:self.avatarView];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.text = self.characterName;
    self.nameLabel.textColor = LumiTextColor();
    self.nameLabel.font = LumiFont(26.0, UIFontWeightBold);
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:self.nameLabel];

    self.taglineLabel = [[UILabel alloc] init];
    self.taglineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.taglineLabel.textColor = LumiMutedColor();
    self.taglineLabel.font = LumiFont(15.0, UIFontWeightRegular);
    self.taglineLabel.textAlignment = NSTextAlignmentCenter;
    self.taglineLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.taglineLabel];

    self.tagsLabel = [[UILabel alloc] init];
    self.tagsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.tagsLabel.textColor = LumiAccentColor();
    self.tagsLabel.font = LumiFont(12.0, UIFontWeightMedium);
    self.tagsLabel.textAlignment = NSTextAlignmentCenter;
    self.tagsLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.tagsLabel];

    UILabel *aboutHeader = [self headerLabel:@"Описание"];
    [self.scrollView addSubview:aboutHeader];

    self.backstoryLabel = [[UILabel alloc] init];
    self.backstoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.backstoryLabel.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    self.backstoryLabel.font = LumiFont(15.0, UIFontWeightRegular);
    self.backstoryLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.backstoryLabel];

    UILabel *firstHeader = [self headerLabel:@"Первое сообщение"];
    [self.scrollView addSubview:firstHeader];

    UIView *messageBox = [[UIView alloc] init];
    messageBox.translatesAutoresizingMaskIntoConstraints = NO;
    messageBox.backgroundColor = LumiSurfaceColor();
    messageBox.layer.cornerRadius = 14.0;
    [self.scrollView addSubview:messageBox];

    self.firstMessageLabel = [[UILabel alloc] init];
    self.firstMessageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.firstMessageLabel.textColor = [UIColor colorWithWhite:0.86 alpha:1.0];
    self.firstMessageLabel.font = LumiFont(14.5, UIFontWeightRegular);
    self.firstMessageLabel.numberOfLines = 0;
    [messageBox addSubview:self.firstMessageLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.firstMessageLabel.topAnchor constraintEqualToAnchor:messageBox.topAnchor constant:14.0],
        [self.firstMessageLabel.bottomAnchor constraintEqualToAnchor:messageBox.bottomAnchor constant:-14.0],
        [self.firstMessageLabel.leadingAnchor constraintEqualToAnchor:messageBox.leadingAnchor constant:14.0],
        [self.firstMessageLabel.trailingAnchor constraintEqualToAnchor:messageBox.trailingAnchor constant:-14.0],
    ]];

    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startButton setTitle:@"Начать чат" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.titleLabel.font = LumiFont(17.0, UIFontWeightSemibold);
    self.startButton.backgroundColor = LumiAccentColor();
    self.startButton.layer.cornerRadius = 14.0;
    [self.startButton addTarget:self action:@selector(startButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.startButton addSubview:self.spinner];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.startButton.topAnchor constant:-10.0],

        [self.avatarView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:18.0],
        [self.avatarView.centerXAnchor constraintEqualToAnchor:self.scrollView.centerXAnchor],
        [self.avatarView.widthAnchor constraintEqualToConstant:120.0],
        [self.avatarView.heightAnchor constraintEqualToConstant:120.0],

        [self.nameLabel.topAnchor constraintEqualToAnchor:self.avatarView.bottomAnchor constant:14.0],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:24.0],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-24.0],

        [self.taglineLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:6.0],
        [self.taglineLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.taglineLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [self.tagsLabel.topAnchor constraintEqualToAnchor:self.taglineLabel.bottomAnchor constant:10.0],
        [self.tagsLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.tagsLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [aboutHeader.topAnchor constraintEqualToAnchor:self.tagsLabel.bottomAnchor constant:28.0],
        [aboutHeader.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [aboutHeader.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [self.backstoryLabel.topAnchor constraintEqualToAnchor:aboutHeader.bottomAnchor constant:8.0],
        [self.backstoryLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.backstoryLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [firstHeader.topAnchor constraintEqualToAnchor:self.backstoryLabel.bottomAnchor constant:26.0],
        [firstHeader.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [firstHeader.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],

        [messageBox.topAnchor constraintEqualToAnchor:firstHeader.bottomAnchor constant:8.0],
        [messageBox.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [messageBox.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [messageBox.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24.0],

        [self.startButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24.0],
        [self.startButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24.0],
        [self.startButton.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-10.0],
        [self.startButton.heightAnchor constraintEqualToConstant:52.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.startButton.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.startButton.centerYAnchor],
    ]];

    [[LumiImageLoader sharedLoader] loadURLString:self.avatarURL intoImageView:self.avatarView];
    [self loadCharacter];
}

- (UILabel *)headerLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.textColor = LumiTextColor();
    label.font = LumiFont(17.0, UIFontWeightSemibold);
    return label;
}

- (void)loadCharacter {
    [[LumiAPIClient sharedClient] fetchCharacterWithID:self.characterID completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            self.backstoryLabel.text = [NSString stringWithFormat:@"Не удалось загрузить персонажа.\n%@", error.localizedDescription];
            return;
        }
        NSString *name = json[@"name"];
        if (name.length) {
            self.characterName = name;
            self.title = name;
            self.nameLabel.text = name;
        }
        NSString *avatar = json[@"avatar_url"];
        if (avatar.length) {
            self.avatarURL = avatar;
            [[LumiImageLoader sharedLoader] loadURLString:avatar intoImageView:self.avatarView];
        }
        self.taglineLabel.text = json[@"tagline"] ?: @"";
        NSArray *tags = json[@"tags"];
        if ([tags isKindOfClass:[NSArray class]]) {
            self.tagsLabel.text = [tags componentsJoinedByString:@" · "];
        }
        self.backstoryLabel.text = json[@"backstory"] ?: @"Описание недоступно.";
        self.firstMessageLabel.text = json[@"first_message"] ?: @"";
    }];
}

- (void)startButtonTapped {
    if (![[LumiAPIClient sharedClient] isAuthenticated]) {
        [self presentAuthWithCompletion:^{
            [self startChat];
        }];
        return;
    }
    [self startChat];
}

- (void)startChat {
    [self.spinner startAnimating];
    self.startButton.enabled = NO;

    NSDictionary *context = @{
        @"character_id": self.characterID,
        @"persona_id": self.characterID,
        @"locale": @"ru",
    };
    [[LumiAPIClient sharedClient] createSessionWithDeviceContext:context completion:^(NSDictionary *json, NSError *error) {
        [self.spinner stopAnimating];
        self.startButton.enabled = YES;

        if (error) {
            [self showAlert:@"Не удалось начать чат" message:error.localizedDescription];
            return;
        }
        NSString *sessionID = json[@"session_id"] ?: json[@"id"];
        if (!sessionID.length && [json[@"session"] isKindOfClass:[NSDictionary class]]) {
            sessionID = json[@"session"][@"id"] ?: json[@"session"][@"session_id"];
        }
        if (!sessionID.length) {
            [self showAlert:@"Не удалось начать чат"
                    message:@"Сервер не вернул идентификатор сессии."];
            return;
        }
        LumiChatViewController *chat = [[LumiChatViewController alloc] initWithSessionID:sessionID
                                                                                   title:self.characterName];
        [self.navigationController pushViewController:chat animated:YES];
    }];
}

- (void)presentAuthWithCompletion:(void (^)(void))completion {
    LumiAuthViewController *auth = [[LumiAuthViewController alloc] init];
    auth.onSuccess = completion;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:auth];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    auth.title = @"Вход";
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
