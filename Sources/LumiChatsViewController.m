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
    NSString *candidates[5];
    NSUInteger count = 0;
    for (NSString *key in @[@"last_message_at", @"updated_at", @"last_activity_at", @"created_at"]) {
        NSString *value = LumiAsString(LumiValue(chat, key));
        if (value.length) {
            candidates[count++] = value;
        }
    }
    NSString *nested = LumiNestedString(chat, @"last_message", @"created_at");
    if (nested.length) {
        candidates[count++] = nested;
    }
    for (NSUInteger index = 0; index < count; index++) {
        NSDate *date = [self parseDate:candidates[index]];
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
            [LumiDiagnostics log:@"чаты: ошибка списка — %@", error.localizedDescription];
            return;
        }
        NSArray *items = LumiAsArray(result) ?: @[];
        [LumiDiagnostics log:@"чаты: получено %lu", (unsigned long)items.count];
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
    return [valid sortedArrayUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
        NSDictionary *left = LumiAsDictionary(leftObject);
        NSDictionary *right = LumiAsDictionary(rightObject);
        id leftDate = nil;
        id rightDate = nil;
        for (NSString *key in @[@"last_message_at", @"updated_at", @"created_at"]) {
            leftDate = LumiValue(left, key) ?: leftDate;
            rightDate = LumiValue(right, key) ?: rightDate;
        }
        return LumiCompareDates(rightDate, leftDate);
    }];
}

- (NSDictionary *)catalogItemForChat:(NSDictionary *)chat {
    NSString *targetID = LumiChatTargetIdentifier(LumiAsDictionary(chat) ?: @{});
    if (!targetID.length) {
        return nil;
    }
    NSString *kind = LumiChatKind(chat);
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    if ([kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"]) {
        return [store storyWithID:targetID];
    }
    if ([kind isEqualToString:@"character"] || [kind isEqualToString:@"characters"]) {
        return [store characterWithID:targetID];
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
    [cell configureWithChat:chat item:[self catalogItemForChat:chat] number:indexPath.row + 1];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.chats.count) {
        return;
    }
    NSDictionary *chat = LumiAsDictionary(self.chats[indexPath.row]);
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

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"Удалить"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        if (indexPath.row >= (NSInteger)weakSelf.chats.count) {
            completionHandler(NO);
            return;
        }
        NSDictionary *chat = weakSelf.chats[indexPath.row];
        NSString *identifier = LumiChatIdentifier(chat);
        if (![identifier isKindOfClass:[NSString class]]) {
            completionHandler(NO);
            return;
        }
        [[LumiAPI sharedClient] deleteChat:identifier completion:^(id result, NSError *error) {
            if (!error) {
                NSMutableArray *chats = [weakSelf.chats mutableCopy];
                if (indexPath.row < (NSInteger)chats.count) {
                    [chats removeObjectAtIndex:indexPath.row];
                    weakSelf.chats = chats;
                    @try {
                        [weakSelf.tableView deleteRowsAtIndexPaths:@[indexPath]
                                                  withRowAnimation:UITableViewRowAnimationAutomatic];
                    } @catch (NSException *exception) {
                        [weakSelf.tableView reloadData];
                    }
                }
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
