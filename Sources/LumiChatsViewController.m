#import "LumiChatsViewController.h"
#import "LumiAPI.h"
#import "LumiCatalogStore.h"
#import "LumiChatViewController.h"
#import "LumiImageLoader.h"
#import "LumiLoginViewController.h"
#import "LumiTheme.h"
#import "LumiWebAuthViewController.h"

@interface LumiSessionCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
- (void)configureWithChat:(NSDictionary *)chat item:(nullable NSDictionary *)item;
@end

@implementation LumiSessionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = LumiBackgroundColor();
        self.contentView.backgroundColor = LumiBackgroundColor();
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.thumb = [[UIImageView alloc] init];
        self.thumb.translatesAutoresizingMaskIntoConstraints = NO;
        self.thumb.contentMode = UIViewContentModeScaleAspectFill;
        self.thumb.clipsToBounds = YES;
        self.thumb.layer.cornerRadius = 26.0;
        self.thumb.backgroundColor = LumiSurfaceColor();
        self.thumb.image = [UIImage imageNamed:@"AvatarPlaceholder"];
        [self.contentView addSubview:self.thumb];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
        self.titleLabel.textColor = LumiTextColor();
        [self.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.font = LumiFont(13.0, UIFontWeightRegular);
        self.subtitleLabel.textColor = LumiMutedColor();
        self.subtitleLabel.numberOfLines = 2;
        [self.contentView addSubview:self.subtitleLabel];

        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = LumiFont(11.0, UIFontWeightRegular);
        self.dateLabel.textColor = LumiMutedColor();
        self.dateLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.dateLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [self.thumb.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.thumb.widthAnchor constraintEqualToConstant:52.0],
            [self.thumb.heightAnchor constraintEqualToConstant:52.0],

            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:12.0],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.dateLabel.leadingAnchor constant:-6.0],

            [self.dateLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14.0],
            [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [self.dateLabel.widthAnchor constraintEqualToConstant:64.0],

            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:3.0],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        ]];
    }
    return self;
}

- (void)configureWithChat:(NSDictionary *)chat item:(NSDictionary *)item {
    NSString *title = chat[@"title"];
    if (![title isKindOfClass:[NSString class]] || !title.length) {
        title = item[@"name"] ?: item[@"title"] ?: chat[@"target"][@"name"];
    }
    self.titleLabel.text = title.length ? title : @"Чат";

    NSString *preview = [self previewFromChat:chat];
    self.subtitleLabel.text = preview.length ? preview : @"Нет сообщений";

    NSDate *date = [self dateFromChat:chat];
    self.dateLabel.text = date ? [self relativeStringFromDate:date] : @"";

    NSString *avatar = chat[@"avatar_url"];
    if (![avatar isKindOfClass:[NSString class]] || !avatar.length) {
        avatar = item[@"avatar_url"] ?: chat[@"target"][@"avatar_url"];
    }
    [self.thumb setImage:nil];
    [[LumiImageLoader sharedLoader] loadURLString:avatar intoImageView:self.thumb];
}

- (NSString *)previewFromChat:(NSDictionary *)chat {
    id last = chat[@"last_message"];
    if ([last isKindOfClass:[NSDictionary class]]) {
        id content = last[@"content"] ?: last[@"text"] ?: last[@"message"];
        if ([content isKindOfClass:[NSString class]]) {
            return content;
        }
    }
    if ([last isKindOfClass:[NSString class]]) {
        return last;
    }
    for (NSString *key in @[@"last_message_preview", @"preview", @"note", @"last_message_text"]) {
        id value = chat[key];
        if ([value isKindOfClass:[NSString class]] && [value length]) {
            return value;
        }
    }
    return nil;
}

- (NSDate *)dateFromChat:(NSDictionary *)chat {
    for (NSString *key in @[@"last_message_at", @"updated_at", @"last_activity_at", @"created_at"]) {
        id value = chat[key];
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSDate *date = [self parseDate:value];
        if (date) {
            return date;
        }
    }
    return nil;
}

- (NSDate *)parseDate:(NSString *)string {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    NSDate *date = [formatter dateFromString:string];
    if (date) {
        return date;
    }
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:string];
}

- (NSString *)relativeStringFromDate:(NSDate *)date {
    NSTimeInterval interval = -[date timeIntervalSinceNow];
    if (interval < 60) {
        return @"сейчас";
    }
    if (interval < 3600) {
        return [NSString stringWithFormat:@"%ld мин", (long)(interval / 60)];
    }
    if (interval < 86400) {
        return [NSString stringWithFormat:@"%ld ч", (long)(interval / 3600)];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"dd.MM";
    return [formatter stringFromDate:date];
}

@end

#pragma mark - Chats

@interface LumiChatsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *loginPrompt;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSArray<NSDictionary *> *chats;
@property (nonatomic, assign) BOOL loading;
@end

@implementation LumiChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = @"Чаты";
    self.chats = @[];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 76.0;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[LumiSessionCell class] forCellReuseIdentifier:@"chat"];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    refreshControl.tintColor = LumiAccentColor();
    [refreshControl addTarget:self action:@selector(refreshPulled) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refreshControl;

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.font = LumiFont(14.0, UIFontWeightRegular);
    self.stateLabel.textColor = LumiMutedColor();
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.numberOfLines = 0;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = LumiAccentColor();
    self.spinner.hidesWhenStopped = YES;

    [self.view addSubview:self.tableView];
    [self.view addSubview:self.stateLabel];
    [self.view addSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stateLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30.0],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30.0],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Каталог"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(openCatalog)];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authChanged)
                                                 name:LumiAuthDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(authChanged)
                                                 name:LumiWebAuthDidCompleteNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(unauthorized)
                                                 name:LumiAPIDidUnauthorizedNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateLoginState];
    if ([[LumiAPI sharedClient] isAuthenticated] && !self.loading) {
        [self loadChats];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - State

- (void)authChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateLoginState];
        if ([[LumiAPI sharedClient] isAuthenticated]) {
            [self loadChats];
        }
    });
}

- (void)unauthorized {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateLoginState];
    });
}

- (void)updateLoginState {
    BOOL authenticated = [[LumiAPI sharedClient] isAuthenticated];
    self.tableView.hidden = !authenticated;
    if (authenticated) {
        [self.loginPrompt removeFromSuperview];
        self.loginPrompt = nil;
        return;
    }
    self.stateLabel.text = nil;
    self.chats = @[];
    [self.tableView reloadData];
    [self showLoginPrompt];
}

- (void)showLoginPrompt {
    if (self.loginPrompt) {
        return;
    }
    UIView *prompt = [[UIView alloc] init];
    prompt.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:prompt];
    self.loginPrompt = prompt;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Чаты вашего аккаунта";
    title.font = LumiFont(20.0, UIFontWeightBold);
    title.textColor = LumiTextColor();
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Войдите в Lumi, чтобы загрузить переписки и продолжить их здесь.";
    subtitle.font = LumiFont(14.0, UIFontWeightRegular);
    subtitle.textColor = LumiMutedColor();
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:@"Войти" forState:UIControlStateNormal];
    button.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = LumiAccentColor();
    button.layer.cornerRadius = 12.0;
    [button addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];

    [prompt addSubview:title];
    [prompt addSubview:subtitle];
    [prompt addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [prompt.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [prompt.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [prompt.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [prompt.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [title.centerYAnchor constraintEqualToAnchor:prompt.centerYAnchor constant:-60.0],
        [title.leadingAnchor constraintEqualToAnchor:prompt.leadingAnchor constant:30.0],
        [title.trailingAnchor constraintEqualToAnchor:prompt.trailingAnchor constant:-30.0],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:prompt.leadingAnchor constant:30.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:prompt.trailingAnchor constant:-30.0],

        [button.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:24.0],
        [button.centerXAnchor constraintEqualToAnchor:prompt.centerXAnchor],
        [button.widthAnchor constraintEqualToConstant:180.0],
        [button.heightAnchor constraintEqualToConstant:50.0],
    ]];
}

- (void)loginTapped {
    LumiLoginViewController *login = [[LumiLoginViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:login];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)openCatalog {
    self.tabBarController.selectedIndex = 0;
}

#pragma mark - Data

- (void)refreshPulled {
    if (![[LumiAPI sharedClient] isAuthenticated]) {
        [self.tableView.refreshControl endRefreshing];
        [self updateLoginState];
        return;
    }
    [self loadChats];
}

- (void)loadChats {
    if (self.loading) {
        return;
    }
    self.loading = YES;
    [self.spinner startAnimating];
    self.stateLabel.text = nil;
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] fetchChatsWithCompletion:^(id result, NSError *error) {
        weakSelf.loading = NO;
        [weakSelf.spinner stopAnimating];
        [weakSelf.tableView.refreshControl endRefreshing];
        if (error) {
            weakSelf.stateLabel.text = error.localizedDescription;
            return;
        }
        NSArray *items = [result isKindOfClass:[NSArray class]] ? result : @[];
        weakSelf.chats = [weakSelf sortedChats:items];
        weakSelf.stateLabel.text = weakSelf.chats.count ? nil : @"Чатов пока нет. Откройте каталог и начните общение.";
        [weakSelf.tableView reloadData];
    }];
}

- (NSArray *)sortedChats:(NSArray *)chats {
    NSMutableArray *valid = [NSMutableArray array];
    for (NSDictionary *chat in chats) {
        if ([chat isKindOfClass:[NSDictionary class]]) {
            [valid addObject:chat];
        }
    }
    return [valid sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSString *leftDate = left[@"last_message_at"] ?: left[@"updated_at"] ?: left[@"created_at"] ?: @"";
        NSString *rightDate = right[@"last_message_at"] ?: right[@"updated_at"] ?: right[@"created_at"] ?: @"";
        return [rightDate compare:leftDate];
    }];
}

- (NSDictionary *)catalogItemForChat:(NSDictionary *)chat {
    id targetID = chat[@"target_id"] ?: chat[@"character_id"] ?: chat[@"story_id"] ?: chat[@"target"][@"id"];
    if (![targetID isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *kind = chat[@"target_kind"] ?: chat[@"kind"] ?: chat[@"target"][@"kind"];
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    if ([kind isKindOfClass:[NSString class]] && [kind isEqualToString:@"story"]) {
        return [store storyWithID:targetID];
    }
    NSDictionary *character = [store characterWithID:targetID];
    return character ?: [store storyWithID:targetID];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LumiSessionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chat" forIndexPath:indexPath];
    NSDictionary *chat = self.chats[indexPath.row];
    [cell configureWithChat:chat item:[self catalogItemForChat:chat]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *chat = self.chats[indexPath.row];
    NSDictionary *item = [self catalogItemForChat:chat] ?: @{};
    LumiDetailKind kind = LumiDetailKindCharacter;
    id kindValue = chat[@"target_kind"] ?: chat[@"kind"] ?: chat[@"target"][@"kind"];
    if ([kindValue isKindOfClass:[NSString class]] && [kindValue isEqualToString:@"story"]) {
        kind = LumiDetailKindStory;
    }
    LumiChatViewController *controller = [[LumiChatViewController alloc] initWithChat:chat item:item kind:kind];
    [self.navigationController pushViewController:controller animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"Удалить"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSDictionary *chat = weakSelf.chats[indexPath.row];
        NSString *identifier = chat[@"id"];
        if (![identifier isKindOfClass:[NSString class]]) {
            completionHandler(NO);
            return;
        }
        [[LumiAPI sharedClient] deleteChat:identifier completion:^(id result, NSError *error) {
            if (!error) {
                NSMutableArray *chats = [weakSelf.chats mutableCopy];
                [chats removeObjectAtIndex:indexPath.row];
                weakSelf.chats = chats;
                [weakSelf.tableView deleteRowsAtIndexPaths:@[indexPath]
                                          withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            completionHandler(error == nil);
        }];
    }];
    delete.backgroundColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.30 alpha:1.0];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[delete]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

@end
