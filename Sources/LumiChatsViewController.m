#import "LumiChatsViewController.h"
#import "LumiAPIClient.h"
#import "LumiAuthViewController.h"
#import "LumiChatViewController.h"
#import "LumiImageLoader.h"
#import "LumiTheme.h"

@interface LumiSessionCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation LumiSessionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = LumiSurfaceColor();
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        self.thumb = [[UIImageView alloc] init];
        self.thumb.translatesAutoresizingMaskIntoConstraints = NO;
        self.thumb.contentMode = UIViewContentModeScaleAspectFill;
        self.thumb.clipsToBounds = YES;
        self.thumb.layer.cornerRadius = 24.0;
        self.thumb.image = [UIImage imageNamed:@"AvatarPlaceholder"];
        [self.contentView addSubview:self.thumb];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.textColor = LumiTextColor();
        self.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
        [self.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.textColor = LumiMutedColor();
        self.subtitleLabel.font = LumiFont(13.0, UIFontWeightRegular);
        self.subtitleLabel.numberOfLines = 1;
        [self.contentView addSubview:self.subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [self.thumb.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.thumb.widthAnchor constraintEqualToConstant:48.0],
            [self.thumb.heightAnchor constraintEqualToConstant:48.0],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:14.0],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.thumb.topAnchor constant:1.0],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4.0],
        ]];
    }
    return self;
}

@end

@interface LumiChatsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) NSArray<NSDictionary *> *sessions;
@end

@implementation LumiChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 76.0;
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 16, 0);
    [self.tableView registerClass:[LumiSessionCell class] forCellReuseIdentifier:@"session"];
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = LumiMutedColor();
    [self.refreshControl addTarget:self action:@selector(loadSessions) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.textColor = LumiMutedColor();
    self.stateLabel.font = LumiFont(15.0, UIFontWeightRegular);
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.numberOfLines = 0;
    self.stateLabel.hidden = YES;
    [self.view addSubview:self.stateLabel];

    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginButton setTitle:@"Войти" forState:UIControlStateNormal];
    [self.loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.loginButton.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    self.loginButton.backgroundColor = LumiAccentColor();
    self.loginButton.layer.cornerRadius = 12.0;
    self.loginButton.hidden = YES;
    [self.loginButton addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.loginButton];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.stateLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30.0],
        [self.stateLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:32.0],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-32.0],
        [self.loginButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loginButton.topAnchor constraintEqualToAnchor:self.stateLabel.bottomAnchor constant:18.0],
        [self.loginButton.widthAnchor constraintEqualToConstant:180.0],
        [self.loginButton.heightAnchor constraintEqualToConstant:44.0],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadForAuthState];
}

- (void)reloadForAuthState {
    if (![[LumiAPIClient sharedClient] isAuthenticated]) {
        self.tableView.hidden = YES;
        self.stateLabel.text = @"Войдите, чтобы видеть свои чаты";
        self.stateLabel.hidden = NO;
        self.loginButton.hidden = NO;
        return;
    }
    self.tableView.hidden = NO;
    self.loginButton.hidden = YES;
    [self loadSessions];
}

- (void)loadSessions {
    [self.spinner startAnimating];
    self.stateLabel.hidden = YES;

    [[LumiAPIClient sharedClient] fetchSessionsWithCompletion:^(NSDictionary *json, NSError *error) {
        [self.spinner stopAnimating];
        [self.refreshControl endRefreshing];

        if (error) {
            self.sessions = @[];
            [self.tableView reloadData];
            self.stateLabel.text = [NSString stringWithFormat:@"Не удалось загрузить чаты.\n%@", error.localizedDescription];
            self.stateLabel.hidden = NO;
            return;
        }

        NSArray *sessions = json[@"results"];
        if (![sessions isKindOfClass:[NSArray class]]) sessions = json[@"sessions"];
        if (![sessions isKindOfClass:[NSArray class]]) sessions = json[@"data"];
        if (![sessions isKindOfClass:[NSArray class]]) sessions = @[];

        self.sessions = sessions;
        [self.tableView reloadData];
        if (!sessions.count) {
            self.stateLabel.text = @"Чатов пока нет.\nНачните с персонажа во вкладке «Персонажи».";
            self.stateLabel.hidden = NO;
        }
    }];
}

- (void)loginTapped {
    LumiAuthViewController *auth = [[LumiAuthViewController alloc] init];
    auth.onSuccess = ^{
        [self reloadForAuthState];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:auth];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    auth.title = @"Вход";
    [self presentViewController:navigation animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sessions.count;
}

- (NSString *)textForMessageValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [self textForMessageValue:(value[@"content"] ?: value[@"text"] ?: value[@"message"])];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LumiSessionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"session" forIndexPath:indexPath];
    NSDictionary *session = self.sessions[indexPath.row];

    NSDictionary *character = session[@"character"] ?: session[@"persona"];
    NSString *title = session[@"title"] ?: session[@"name"];
    if (!title.length && [character isKindOfClass:[NSDictionary class]]) {
        title = character[@"name"];
    }
    if (!title.length) {
        title = @"Чат";
    }
    cell.titleLabel.text = title;

    NSString *subtitle = [self textForMessageValue:session[@"last_message"]];
    if (!subtitle.length) {
        subtitle = session[@"updated_at"] ?: session[@"created_at"] ?: @"";
    }
    cell.subtitleLabel.text = subtitle;

    NSString *avatar = session[@"avatar_url"];
    if (!avatar.length && [character isKindOfClass:[NSDictionary class]]) {
        avatar = character[@"avatar_url"];
    }
    [[LumiImageLoader sharedLoader] loadURLString:avatar intoImageView:cell.thumb];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *session = self.sessions[indexPath.row];
    NSString *sessionID = session[@"id"] ?: session[@"session_id"];
    if (!sessionID.length) {
        return;
    }
    NSDictionary *character = session[@"character"] ?: session[@"persona"];
    NSString *title = session[@"title"] ?: session[@"name"];
    if (!title.length && [character isKindOfClass:[NSDictionary class]]) {
        title = character[@"name"];
    }
    LumiChatViewController *chat = [[LumiChatViewController alloc] initWithSessionID:sessionID
                                                                               title:title ?: @"Чат"];
    [self.navigationController pushViewController:chat animated:YES];
}

@end
