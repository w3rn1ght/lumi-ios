#import "LumiChatsViewController.h"
#import "LumiAPI.h"
#import "LumiCatalogStore.h"
#import "LumiChatViewController.h"
#import "LumiImageLoader.h"
#import "LumiLoginViewController.h"
#import "LumiRichText.h"
#import "LumiSafe.h"
#import "LumiDiagnostics.h"
#import "LumiTheme.h"


static NSString *LumiChatIdentifier(NSDictionary *chat) {
    for (NSString *key in @[@"id", @"chat_id", @"session_id"]) {
        NSString *value = LumiAsString(chat[key]);
        if (value.length) {
            return value;
        }
    }
    return nil;
}

static NSString *LumiChatKind(NSDictionary *chat) {
    for (NSString *key in @[@"target_kind", @"kind", @"target_type", @"type"]) {
        NSString *value = LumiAsString(chat[key]);
        if (value.length) {
            return value;
        }
    }
    NSString *nested = LumiNestedString(chat, @"target", @"kind");
    return nested.length ? nested : LumiNestedString(chat, @"target", @"type");
}

static NSString *LumiChatTargetIdentifier(NSDictionary *chat) {
    for (NSString *key in @[@"target_id", @"character_id", @"story_id", @"targetId"]) {
        NSString *value = LumiAsString(chat[key]);
        if (value.length) {
            return value;
        }
    }
    NSString *nested = LumiNestedString(chat, @"target", @"id");
    return nested.length ? nested : LumiNestedString(chat, @"target", @"character_id");
}

@interface LumiSessionCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
- (void)configureWithChat:(NSDictionary *)chat item:(nullable NSDictionary *)item number:(NSUInteger)number;
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

- (void)configureWithChat:(NSDictionary *)chat item:(nullable NSDictionary *)item number:(NSUInteger)number {
    chat = LumiAsDictionary(chat) ?: @{};
    item = LumiAsDictionary(item);
    NSString *name = LumiAsString(item[@"name"]) ?: LumiAsString(item[@"title"]);
    if (!name.length) {
        name = LumiAsString(chat[@"title"]);
    }
    if (!name.length) {
        name = LumiNestedString(chat, @"target", @"name");
    }
    if (!name.length) {
        name = LumiChatKind(chat) && [LumiChatKind(chat) isEqualToString:@"story"] ? @"История" : @"Персонаж";
    }
    self.titleLabel.text = name;

    NSString *preview = [self previewFromChat:chat];
    self.subtitleLabel.text = preview.length ? preview : @"Нет сообщений";

    NSDate *date = [self dateFromChat:chat];
    self.dateLabel.text = date ? [self relativeStringFromDate:date] : @"";

    NSString *avatar = LumiAsString(chat[@"avatar_url"]);
    if (!avatar.length) {
        avatar = LumiAsString(item[@"avatar_url"]);
    }
    if (!avatar.length) {
        avatar = LumiNestedString(chat, @"target", @"avatar_url");
    }
    [self.thumb setImage:nil];
    if (avatar.length) {
        [[LumiImageLoader sharedLoader] loadURLString:avatar intoImageView:self.thumb];
    } else {
        self.thumb.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    }
}

- (NSString *)previewFromChat:(NSDictionary *)chat {
    id last = LumiValue(chat, @"last_message");
    NSString *content = nil;
    if ([last isKindOfClass:[NSDictionary class]]) {
        content = LumiStringValue(LumiValue(last, @"content"))
            ?: LumiStringValue(LumiValue(last, @"text"))
            ?: LumiStringValue(LumiValue(last, @"message"));
    } else {
        content = LumiStringValue(last);
    }
    if (!content.length) {
        for (NSString *key in @[@"last_message_preview", @"preview", @"note", @"last_message_text"]) {
            content = LumiStringValue(LumiValue(chat, key));
            if (content.length) {
                break;
            }
        }
    }
    if (!content.length) {
        return nil;
    }
    BOOL hadPhoto = [LumiRichTextRenderer imageURLsInText:content].count > 0;
    NSString *stripped = [LumiRichTextRenderer stringByStrippingImageMarkers:content];
    stripped = [[stripped componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                componentsJoinedByString:@" "];
    stripped = [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!stripped.length && hadPhoto) {
        return @"Фотография";
    }
    return stripped.length ? stripped : nil;
}

- (NSDate *)dateFromChat:(NSDictionary *)chat {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSString *key in @[@"last_message_at", @"last_activity_at", @"updated_at", @"created_at"]) {
        NSString *value = LumiAsString(LumiValue(chat, key));
        if (value.length) {
            [candidates addObject:value];
        }
    }
    id lastMessage = LumiValue(chat, @"last_message") ?: LumiValue(chat, @"lastMessage");
    for (NSString *key in @[@"created_at", @"sent_at", @"updated_at"]) {
        NSString *value = LumiAsString(LumiValue(lastMessage, key));
        if (value.length) {
            [candidates addObject:value];
        }
    }
    for (NSString *candidate in candidates) {
        NSDate *date = [self parseDate:candidate];
        if (date) {
            return date;
        }
    }
    return nil;
}

- (NSDate *)parseDate:(NSString *)string {
    return LumiDateFromValue(string);
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

@interface LumiChatGroup : NSObject
@property (nonatomic, copy) NSString *targetID;
@property (nonatomic, copy) NSString *targetKind;
@property (nonatomic, copy) NSString *targetName;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, strong) NSArray<NSDictionary *> *chats;
@property (nonatomic, assign) NSDate *lastActivityDate;
@end

@implementation LumiChatGroup
@end

@interface LumiChatsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *loginPrompt;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSArray<NSDictionary *> *chats; // плоский массив для совместимости
@property (nonatomic, strong) NSArray<LumiChatGroup *> *chatGroups; // сгруппированные чаты
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *resolvedItems;
@property (nonatomic, assign) BOOL loading;
- (NSDate *)parseDate:(NSString *)string;
- (NSDate *)lastActivityDateFromChat:(NSDictionary *)chat;
- (void)resolveMissingNames;
@end

@implementation LumiChatsViewController

- (NSDate *)parseDate:(NSString *)string {
    return LumiDateFromValue(string);
}

- (NSDate *)lastActivityDateFromChat:(NSDictionary *)chat {
    if (![chat isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSString *key in @[@"last_message_at", @"last_activity_at", @"updated_at", @"created_at"]) {
        id value = LumiValue(chat, key);
        if (value) {
            [candidates addObject:value];
        }
    }
    id lastMessage = LumiValue(chat, @"last_message") ?: LumiValue(chat, @"lastMessage");
    for (NSString *key in @[@"created_at", @"sent_at", @"updated_at"]) {
        id value = LumiValue(lastMessage, key);
        if (value) {
            [candidates addObject:value];
        }
    }
    for (id candidate in candidates) {
        NSDate *date = LumiDateFromValue(candidate);
        if (date) {
            return date;
        }
    }
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = @"Чаты";
    self.chats = @[];
    self.resolvedItems = [NSMutableDictionary dictionary];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
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
                                             selector:@selector(unauthorized)
                                                 name:LumiAPIDidUnauthorizedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogDidUpdate)
                                                 name:LumiCatalogDidUpdateNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateLoginState];
    if ([[LumiAPI sharedClient] isAuthenticated] && !self.loading) {
        LumiCatalogStore *store = [LumiCatalogStore sharedStore];
        if (!store.isSyncing) {
            [self loadChats];
        }
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
            LumiCatalogStore *store = [LumiCatalogStore sharedStore];
            if (!store.isSyncing) {
                [self loadChats];
            }
        }
    });
}

- (void)unauthorized {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateLoginState];
    });
}

- (void)catalogDidUpdate {
    dispatch_async(dispatch_get_main_queue(), ^{
        LumiCatalogStore *store = [LumiCatalogStore sharedStore];
        // Only reload chats when catalog sync is fully complete (not during incremental page loads)
        if ([[LumiAPI sharedClient] isAuthenticated] && !self.loading && !store.isSyncing) {
            [self loadChats];
        }
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
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    if (store.isSyncing) {
        [self.tableView.refreshControl endRefreshing];
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
            [LumiDiagnostics log:@"чаты: ошибка списка — %@", error.localizedDescription];
            return;
        }
        NSArray *items = LumiAsArray(result) ?: @[];
        [LumiDiagnostics log:@"чаты: получено %lu", (unsigned long)items.count];
        weakSelf.chats = [weakSelf sortedChats:items];
        weakSelf.chatGroups = [weakSelf groupedChats:weakSelf.chats];
        weakSelf.stateLabel.text = weakSelf.chats.count ? nil : @"Чатов пока нет. Откройте каталог и начните общение.";
        [weakSelf.tableView reloadData];
        [weakSelf resolveMissingNames];
    }];
}

- (NSArray *)sortedChats:(NSArray *)chats {
    NSMutableArray *valid = [NSMutableArray array];
    for (NSDictionary *chat in chats) {
        if ([chat isKindOfClass:[NSDictionary class]]) {
            [valid addObject:chat];
        }
    }
    return [valid sortedArrayUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
        NSDictionary *left = LumiAsDictionary(leftObject);
        NSDictionary *right = LumiAsDictionary(rightObject);
        NSDate *leftDate = [self lastActivityDateFromChat:left ?: @{}];
        NSDate *rightDate = [self lastActivityDateFromChat:right ?: @{}];
        if (!leftDate && !rightDate) {
            return NSOrderedSame;
        }
        if (!leftDate) {
            return NSOrderedDescending;
        }
        if (!rightDate) {
            return NSOrderedAscending;
        }
        return [rightDate compare:leftDate];
    }];
}

- (NSArray<LumiChatGroup *> *)groupedChats:(NSArray *)chats {
    // Группируем чаты по target_id + target_kind
    NSMutableDictionary<NSString *, NSMutableArray *> *groupsDict = [NSMutableDictionary dictionary];
    
    for (NSDictionary *chat in chats) {
        NSString *targetID = LumiChatTargetIdentifier(chat);
        NSString *kind = LumiChatKind(chat);
        if (!targetID.length) {
            // Never hide a chat just because the server omitted the target:
            // keep it as its own single-chat group.
            targetID = LumiChatIdentifier(chat);
            if (!kind.length) {
                kind = @"chat";
            }
        }
        if (!targetID.length) {
            continue;
        }
        if (!kind.length) {
            kind = @"character";
        }
        NSString *groupKey = [NSString stringWithFormat:@"%@:%@", kind, targetID];
        NSMutableArray *groupChats = groupsDict[groupKey];
        if (!groupChats) {
            groupChats = [NSMutableArray array];
            groupsDict[groupKey] = groupChats;
        }
        [groupChats addObject:chat];
    }
    
    // Создаем объекты LumiChatGroup
    NSMutableArray<LumiChatGroup *> *groups = [NSMutableArray array];
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    
    for (NSString *groupKey in groupsDict) {
        NSArray *groupChats = groupsDict[groupKey];
        if (groupChats.count == 0) continue;
        
        // Берем первый чат для получения информации о персонаже
        NSDictionary *firstChat = groupChats[0];
        NSString *targetID = LumiChatTargetIdentifier(firstChat);
        NSString *kind = LumiChatKind(firstChat);
        if (!targetID.length) {
            targetID = LumiChatIdentifier(firstChat);
            if (!kind.length) {
                kind = @"chat";
            }
        }
        if (!kind.length) {
            kind = @"character";
        }
        
        // Находим имя и аватар из каталога
        NSString *targetName = nil;
        NSString *avatarURL = nil;
        NSDictionary *catalogItem = [self catalogItemForChat:firstChat];
        if (catalogItem) {
            targetName = LumiAsString(catalogItem[@"name"]) ?: LumiAsString(catalogItem[@"title"]);
            avatarURL = LumiAsString(catalogItem[@"avatar_url"]);
        }
        if (!targetName.length) {
            targetName = LumiNestedString(firstChat, @"target", @"name");
        }
        if (!targetName.length) {
            targetName = LumiAsString(firstChat[@"title"]);
        }
        if (!targetName.length) {
            targetName = [kind isEqualToString:@"story"] ? @"История" : @"Персонаж";
        }
        if (!avatarURL.length) {
            avatarURL = LumiNestedString(firstChat, @"target", @"avatar_url");
        }
        if (!avatarURL.length) {
            avatarURL = LumiAsString(firstChat[@"avatar_url"]);
        }
        
        // Находим дату последней активности в группе
        NSDate *lastDate = nil;
        for (NSDictionary *chat in groupChats) {
            NSDate *date = [self lastActivityDateFromChat:chat];
            if (date && (!lastDate || [date compare:lastDate] == NSOrderedDescending)) {
                lastDate = date;
            }
        }
        
        LumiChatGroup *group = [[LumiChatGroup alloc] init];
        group.targetID = targetID;
        group.targetKind = kind;
        group.targetName = targetName;
        group.avatarURL = avatarURL;
        group.chats = groupChats;
        group.lastActivityDate = lastDate;
        [groups addObject:group];
    }
    
    // Сортируем группы по дате последней активности
    return [groups sortedArrayUsingComparator:^NSComparisonResult(LumiChatGroup *left, LumiChatGroup *right) {
        if (!left.lastActivityDate && !right.lastActivityDate) return NSOrderedSame;
        if (!left.lastActivityDate) return NSOrderedDescending;
        if (!right.lastActivityDate) return NSOrderedAscending;
        return [right.lastActivityDate compare:left.lastActivityDate]; // DESC - новые сверху
    }];
}

- (NSDictionary *)catalogItemForChat:(NSDictionary *)chat {
    NSString *targetID = LumiChatTargetIdentifier(LumiAsDictionary(chat) ?: @{});
    if (!targetID.length) {
        return nil;
    }
    NSString *kind = LumiChatKind(chat);
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    NSDictionary *resolved = self.resolvedItems[targetID];
    if (resolved) {
        return resolved;
    }
    if ([kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"]) {
        return [store storyWithID:targetID];
    }
    if ([kind isEqualToString:@"character"] || [kind isEqualToString:@"characters"]) {
        return [store characterWithID:targetID];
    }
    NSDictionary *character = [store characterWithID:targetID];
    return character ?: [store storyWithID:targetID];
}

- (BOOL)isPlaceholderChatName:(NSString *)name {
    return !name.length || [name isEqualToString:@"Персонаж"] || [name isEqualToString:@"История"];
}

/// The catalog is ~2000 cards and may still be syncing when the chat list is
/// shown, so a group can start with a generic title. Resolve such groups from
/// the public card endpoint (works without a session) and refresh its header.
- (void)resolveMissingNames {
    __weak typeof(self) weakSelf = self;
    [self.chatGroups enumerateObjectsUsingBlock:^(LumiChatGroup *group, NSUInteger index, BOOL *stop) {
        if (![self isPlaceholderChatName:group.targetName]) {
            return;
        }
        NSString *identifier = group.targetID;
        if (!identifier.length) {
            return;
        }
        NSString *kind = group.targetKind ?: @"";
        BOOL isStory = [kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"];
        LumiAPICompletion completion = ^(id result, NSError *error) {
            NSDictionary *detail = LumiAsDictionary(result);
            NSString *name = LumiAsString(detail[@"name"]) ?: LumiAsString(detail[@"title"]);
            if (!name.length) {
                return;
            }
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                LumiChatGroup *target = nil;
                if (index < strongSelf.chatGroups.count) {
                    LumiChatGroup *candidate = strongSelf.chatGroups[index];
                    if ([candidate.targetID isEqualToString:group.targetID]) {
                        target = candidate;
                    }
                }
                if (!target) {
                    for (LumiChatGroup *candidate in strongSelf.chatGroups) {
                        if ([candidate.targetID isEqualToString:group.targetID] &&
                            [candidate.targetKind isEqualToString:group.targetKind]) {
                            target = candidate;
                            break;
                        }
                    }
                }
                if (!target) {
                    return;
                }
                target.targetName = name;
                NSString *avatar = LumiAsString(detail[@"avatar_url"]);
                if (avatar.length) {
                    target.avatarURL = avatar;
                }
                strongSelf.resolvedItems[target.targetID] = detail;
                NSUInteger section = [strongSelf.chatGroups indexOfObjectIdenticalTo:target];
                if (section != NSNotFound && section < (NSUInteger)[strongSelf numberOfSectionsInTableView:strongSelf.tableView]) {
                    [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:section]
                                        withRowAnimation:UITableViewRowAnimationNone];
                }
            });
        };
        if (isStory) {
            [[LumiAPI sharedClient] fetchStoryWithID:identifier completion:completion];
        } else {
            [[LumiAPI sharedClient] fetchCharacterWithID:identifier completion:completion];
        }
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.chatGroups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.chatGroups.count) {
        return 0;
    }
    LumiChatGroup *group = self.chatGroups[section];
    return group.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= (NSInteger)self.chatGroups.count) {
        return [tableView dequeueReusableCellWithIdentifier:@"chat" forIndexPath:indexPath];
    }
    LumiChatGroup *group = self.chatGroups[indexPath.section];
    if (indexPath.row >= (NSInteger)group.chats.count) {
        return [tableView dequeueReusableCellWithIdentifier:@"chat" forIndexPath:indexPath];
    }
    LumiSessionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chat" forIndexPath:indexPath];
    NSDictionary *chat = group.chats[indexPath.row];
    [cell configureWithChat:chat item:[self catalogItemForChat:chat] number:indexPath.row + 1];
    return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section >= (NSInteger)self.chatGroups.count) {
        return nil;
    }
    LumiChatGroup *group = self.chatGroups[section];
    
    UIView *headerView = [[UIView alloc] init];
    headerView.backgroundColor = LumiBackgroundColor();
    
    UIImageView *avatarView = [[UIImageView alloc] init];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.clipsToBounds = YES;
    avatarView.layer.cornerRadius = 18.0;
    avatarView.backgroundColor = LumiSurfaceColor();
    avatarView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    [headerView addSubview:avatarView];
    
    if (group.avatarURL.length) {
        [[LumiImageLoader sharedLoader] loadURLString:group.avatarURL intoImageView:avatarView];
    }
    
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.font = LumiFont(15.0, UIFontWeightSemibold);
    nameLabel.textColor = LumiTextColor();
    nameLabel.text = group.targetName;
    [headerView addSubview:nameLabel];
    
    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countLabel.font = LumiFont(12.0, UIFontWeightRegular);
    countLabel.textColor = LumiMutedColor();
    countLabel.text = [NSString stringWithFormat:@"%lu чат%@", (unsigned long)group.chats.count, 
                       group.chats.count == 1 ? @"" : (group.chats.count < 5 ? @"а" : @"ов")];
    [headerView addSubview:countLabel];
    
    // Кнопка "Новый чат с этим персонажем" в хедере
    UIButton *newChatButton = [UIButton buttonWithType:UIButtonTypeSystem];
    newChatButton.translatesAutoresizingMaskIntoConstraints = NO;
    [newChatButton setTitle:@"＋ Новый чат" forState:UIControlStateNormal];
    newChatButton.titleLabel.font = LumiFont(13.0, UIFontWeightMedium);
    [newChatButton setTitleColor:LumiAccentColor() forState:UIControlStateNormal];
    [newChatButton addTarget:self action:@selector(newChatWithCharacterFromHeader:) forControlEvents:UIControlEventTouchUpInside];
    newChatButton.tag = section;
    [headerView addSubview:newChatButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [headerView.heightAnchor constraintEqualToConstant:56.0],
        
        [avatarView.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:16.0],
        [avatarView.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:36.0],
        [avatarView.heightAnchor constraintEqualToConstant:36.0],
        
        [nameLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor constant:12.0],
        [nameLabel.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor constant:-8.0],
        [nameLabel.trailingAnchor constraintEqualToAnchor:newChatButton.leadingAnchor constant:-8.0],
        
        [countLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [countLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:1.0],
        [countLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        
        [newChatButton.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-16.0],
        [newChatButton.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
        [newChatButton.widthAnchor constraintEqualToConstant:100.0],
        [newChatButton.heightAnchor constraintEqualToConstant:30.0],
    ]];
    
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 56.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= (NSInteger)self.chatGroups.count) {
        return;
    }
    LumiChatGroup *group = self.chatGroups[indexPath.section];
    if (indexPath.row >= (NSInteger)group.chats.count) {
        return;
    }
    NSDictionary *chat = LumiAsDictionary(group.chats[indexPath.row]);
    if (!chat) {
        return;
    }
    NSString *identifier = LumiChatIdentifier(chat);
    if (!identifier.length) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось открыть чат"
                                                                       message:@"Сервер не вернул идентификатор чата. Потяните список вниз, чтобы обновить его."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSDictionary *item = [self catalogItemForChat:chat] ?: @{};
    NSString *kindValue = LumiChatKind(chat);
    LumiDetailKind kind = ([kindValue isEqualToString:@"story"] || [kindValue isEqualToString:@"stories"])
        ? LumiDetailKindStory : LumiDetailKindCharacter;
    LumiChatViewController *controller = [[LumiChatViewController alloc] initWithChat:chat item:item kind:kind];
    controller.chatNumber = (NSUInteger)(indexPath.row + 1);
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)newChatWithCharacterFromHeader:(UIButton *)sender {
    NSInteger section = sender.tag;
    if (section >= (NSInteger)self.chatGroups.count) {
        return;
    }
    LumiChatGroup *group = self.chatGroups[section];
    if (group.chats.count == 0) {
        return;
    }
    
    NSString *targetID = group.targetID;
    NSString *kind = group.targetKind;
    NSDictionary *item = @{@"id": targetID,
                           @"name": group.targetName,
                           @"avatar_url": group.avatarURL};
    
    LumiDetailKind detailKind = ([kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"])
        ? LumiDetailKindStory : LumiDetailKindCharacter;
    
    __weak typeof(self) weakSelf = self;
    LumiAPICompletion completion = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось открыть чат"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        NSDictionary *chat = result;
        LumiChatViewController *controller = [[LumiChatViewController alloc] initWithChat:chat item:item kind:detailKind];
        [strongSelf.navigationController pushViewController:controller animated:YES];
    };
    
    LumiAPI *api = [LumiAPI sharedClient];
    if (detailKind == LumiDetailKindStory) {
        [api openChatWithCharacterID:nil storyID:targetID completion:completion];
    } else {
        [api openChatWithCharacterID:targetID storyID:nil completion:completion];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    
    if (indexPath.section >= (NSInteger)weakSelf.chatGroups.count) {
        return nil;
    }
    LumiChatGroup *group = weakSelf.chatGroups[indexPath.section];
    if (indexPath.row >= (NSInteger)group.chats.count) {
        return nil;
    }
    NSDictionary *chat = group.chats[indexPath.row];
    NSString *identifier = LumiChatIdentifier(chat);
    if (![identifier isKindOfClass:[NSString class]]) {
        return nil;
    }
    
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"Удалить"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [[LumiAPI sharedClient] deleteChat:identifier completion:^(id result, NSError *error) {
            if (!error) {
                NSMutableArray *groupChats = [group.chats mutableCopy];
                if (indexPath.row < (NSInteger)groupChats.count) {
                    [groupChats removeObjectAtIndex:indexPath.row];
                    group.chats = groupChats;
                    @try {
                        [weakSelf.tableView deleteRowsAtIndexPaths:@[indexPath]
                                                  withRowAnimation:UITableViewRowAnimationAutomatic];
                        if (groupChats.count == 0) {
                            NSMutableArray *groups = [weakSelf.chatGroups mutableCopy];
                            [groups removeObjectAtIndex:indexPath.section];
                            weakSelf.chatGroups = groups;
                            [weakSelf.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section]
                                              withRowAnimation:UITableViewRowAnimationAutomatic];
                        }
                    } @catch (NSException *exception) {
                        [weakSelf.tableView reloadData];
                    }
                }
            }
            completionHandler(error == nil);
        }];
    }];
    delete.backgroundColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.30 alpha:1.0];
    
    UIContextualAction *newChat = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                          title:@"Новый чат"
                                                                        handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        if (indexPath.section >= (NSInteger)weakSelf.chatGroups.count) {
            completionHandler(NO);
            return;
        }
        LumiChatGroup *group = weakSelf.chatGroups[indexPath.section];
        NSString *targetID = group.targetID;
        NSString *kind = group.targetKind;
        NSDictionary *item = @{@"id": targetID,
                               @"name": group.targetName,
                               @"avatar_url": group.avatarURL};
        
        LumiDetailKind detailKind = ([kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"])
            ? LumiDetailKindStory : LumiDetailKindCharacter;
        
        __weak typeof(weakSelf) weakSelf2 = weakSelf;
        LumiAPICompletion completion = ^(id result, NSError *error) {
            __strong typeof(weakSelf2) strongSelf = weakSelf2;
            if (!strongSelf) return;
            
            if (error || ![result isKindOfClass:[NSDictionary class]]) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось открыть чат"
                                                                               message:error.localizedDescription
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
                completionHandler(NO);
                return;
            }
            
            NSDictionary *newChatDict = result;
            LumiChatViewController *controller = [[LumiChatViewController alloc] initWithChat:newChatDict item:item kind:detailKind];
            [strongSelf.navigationController pushViewController:controller animated:YES];
            completionHandler(YES);
        };
        
        LumiAPI *api = [LumiAPI sharedClient];
        if (detailKind == LumiDetailKindStory) {
            [api openChatWithCharacterID:nil storyID:targetID completion:completion];
        } else {
            [api openChatWithCharacterID:targetID storyID:nil completion:completion];
        }
    }];
    newChat.backgroundColor = LumiAccentColor();
    
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[delete, newChat]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

@end
