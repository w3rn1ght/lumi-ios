#import "LumiChatViewController.h"
#import "LumiAPI.h"
#import "LumiCatalogStore.h"
#import "LumiImageLoader.h"
#import "LumiTheme.h"

@interface LumiMessageCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *bubbleLabel;
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *trailingConstraint;
@end

@implementation LumiMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.bubble = [[UIView alloc] init];
        self.bubble.translatesAutoresizingMaskIntoConstraints = NO;
        self.bubble.layer.cornerRadius = 16.0;
        [self.contentView addSubview:self.bubble];

        self.bubbleLabel = [[UILabel alloc] init];
        self.bubbleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.bubbleLabel.font = LumiFont(15.0, UIFontWeightRegular);
        self.bubbleLabel.numberOfLines = 0;
        [self.bubble addSubview:self.bubbleLabel];

        self.leadingConstraint = [self.bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0];
        self.trailingConstraint = [self.bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0];

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-10.0],
            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:13.0],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-13.0],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text isUser:(BOOL)isUser pending:(BOOL)pending {
    self.bubbleLabel.text = text.length ? text : (pending ? @"…" : @"");
    self.bubble.backgroundColor = isUser ? LumiAccentColor() : LumiSurfaceColor();
    self.bubbleLabel.textColor = isUser ? [UIColor whiteColor] : LumiTextColor();
    self.leadingConstraint.active = !isUser;
    self.trailingConstraint.active = isUser;
}

@end

#pragma mark - Chat

@interface LumiChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) NSDictionary *chat;
@property (nonatomic, copy) NSString *chatID;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSLayoutConstraint *inputBottomConstraint;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *messages;
@property (nonatomic, assign) BOOL sending;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL hasMore;
@property (nonatomic, strong, nullable) LumiChatStream *stream;
@end

@implementation LumiChatViewController

- (instancetype)initWithChat:(NSDictionary *)chat
                        item:(NSDictionary *)item
                        kind:(LumiDetailKind)kind {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _chat = [self normalizedChat:chat];
        _chatID = [self chatIdentifierFromChat:chat] ?: @"";
        _messages = [NSMutableArray array];
        if (kind == LumiDetailKindStory) {
            _chatTitle = item[@"title"] ?: _chat[@"title"];
            _avatarURL = item[@"avatar_url"];
        } else {
            _chatTitle = item[@"name"] ?: _chat[@"title"];
            _avatarURL = item[@"avatar_url"];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = self.chatTitle.length ? self.chatTitle : @"Чат";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.contentInset = UIEdgeInsetsMake(10.0, 0, 10.0, 0);
    [self.tableView registerClass:[LumiMessageCell class] forCellReuseIdentifier:@"message"];
    [self.view addSubview:self.tableView];

    self.inputBar = [[UIView alloc] init];
    self.inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputBar.backgroundColor = LumiSurfaceColor();
    [self.view addSubview:self.inputBar];

    self.inputField = [[UITextField alloc] init];
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.backgroundColor = LumiElevatedColor();
    self.inputField.textColor = LumiTextColor();
    self.inputField.tintColor = LumiAccentColor();
    self.inputField.font = LumiFont(15.0, UIFontWeightRegular);
    self.inputField.layer.cornerRadius = 18.0;
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    self.inputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Сообщение…"
                                                                           attributes:@{NSForegroundColorAttributeName: LumiMutedColor()}];
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)];
    self.inputField.leftView = spacer;
    self.inputField.leftViewMode = UITextFieldViewModeAlways;
    [self.inputBar addSubview:self.inputField];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton setTitle:@"→" forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    [self.sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.sendButton.backgroundColor = LumiAccentColor();
    self.sendButton.layer.cornerRadius = 19.0;
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.sendButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = LumiAccentColor();
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.font = LumiFont(13.0, UIFontWeightRegular);
    self.stateLabel.textColor = LumiMutedColor();
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.numberOfLines = 0;
    [self.view addSubview:self.stateLabel];

    self.inputBottomConstraint = [self.inputBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],

        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottomConstraint,
        [self.inputBar.heightAnchor constraintEqualToConstant:56.0],

        [self.inputField.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:12.0],
        [self.inputField.centerYAnchor constraintEqualToAnchor:self.inputBar.centerYAnchor],
        [self.inputField.heightAnchor constraintEqualToConstant:38.0],
        [self.inputField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-8.0],

        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-12.0],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.inputBar.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:38.0],
        [self.sendButton.heightAnchor constraintEqualToConstant:38.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.stateLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    [self loadMessages];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.stream cancel];
}

#pragma mark - Chat parsing

- (NSString *)chatIdentifierFromChat:(NSDictionary *)chat {
    id identifier = chat[@"id"] ?: chat[@"chat_id"];
    return [identifier isKindOfClass:[NSString class]] ? identifier : nil;
}

- (NSDictionary *)normalizedChat:(NSDictionary *)chat {
    if (![chat isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSMutableDictionary *result = [chat mutableCopy];
    NSDictionary *nested = chat[@"chat"];
    if (![nested isKindOfClass:[NSDictionary class]]) {
        NSDictionary *target = chat[@"target"];
        if ([target isKindOfClass:[NSDictionary class]]) {
            result[@"title"] = chat[@"title"] ?: target[@"name"];
            result[@"avatar_url"] = target[@"avatar_url"];
        }
    }
    return result;
}

#pragma mark - Loading

- (void)loadMessages {
    if (!self.chatID.length) {
        self.stateLabel.text = @"Не удалось определить чат";
        return;
    }
    self.loading = YES;
    [self.spinner startAnimating];
    self.stateLabel.text = nil;
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] fetchMessagesForChatID:self.chatID
                                            limit:50
                                           before:nil
                                       completion:^(id result, NSError *error) {
        [weakSelf.spinner stopAnimating];
        weakSelf.loading = NO;
        if (error) {
            weakSelf.stateLabel.text = error.localizedDescription;
            return;
        }
        NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        NSArray *rawMessages = dictionary[@"messages"];
        weakSelf.hasMore = [dictionary[@"has_more"] boolValue];
        [weakSelf.messages removeAllObjects];
        if ([rawMessages isKindOfClass:[NSArray class]]) {
            for (NSDictionary *message in rawMessages) {
                NSMutableDictionary *normalized = [weakSelf normalizedMessage:message];
                if (normalized) {
                    [weakSelf.messages addObject:normalized];
                }
            }
        }
        if (!weakSelf.messages.count) {
            [weakSelf seedIntroIfNeeded];
            return;
        }
        [weakSelf sortAndReload];
        [[LumiAPI sharedClient] markChatRead:weakSelf.chatID];
    }];
}

- (void)seedIntroIfNeeded {
    self.stateLabel.text = @"Готовим вступление…";
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] seedIntroForChat:self.chatID completion:^(id result, NSError *error) {
        [weakSelf.spinner stopAnimating];
        weakSelf.stateLabel.text = error ? error.localizedDescription : nil;
        if (!error) {
            [weakSelf reloadAfterSeed];
        }
    }];
}

- (void)reloadAfterSeed {
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] fetchMessagesForChatID:self.chatID limit:50 before:nil completion:^(id result, NSError *error) {
        NSDictionary *dictionary = [result isKindOfClass:[NSDictionary class]] ? result : @{};
        NSArray *rawMessages = dictionary[@"messages"];
        [weakSelf.messages removeAllObjects];
        if ([rawMessages isKindOfClass:[NSArray class]]) {
            for (NSDictionary *message in rawMessages) {
                NSMutableDictionary *normalized = [weakSelf normalizedMessage:message];
                if (normalized) {
                    [weakSelf.messages addObject:normalized];
                }
            }
        }
        [weakSelf sortAndReload];
    }];
}

- (NSMutableDictionary *)normalizedMessage:(NSDictionary *)message {
    if (![message isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *content = message[@"content"];
    if (![content isKindOfClass:[NSString class]]) {
        content = [message[@"text"] isKindOfClass:[NSString class]] ? message[@"text"] : nil;
    }
    if (![content isKindOfClass:[NSString class]]) {
        content = [message[@"message"] isKindOfClass:[NSString class]] ? message[@"message"] : nil;
    }
    if (![content isKindOfClass:[NSString class]]) {
        content = @"";
    }
    BOOL isUser = NO;
    NSString *role = message[@"role"] ?: message[@"sender"] ?: message[@"author"];
    if ([role isKindOfClass:[NSString class]]) {
        isUser = [role isEqualToString:@"user"] || [role isEqualToString:@"human"];
    }
    if (message[@"is_user"]) {
        isUser = [message[@"is_user"] boolValue];
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"content"] = content;
    result[@"is_user"] = @(isUser);
    if (message[@"id"]) {
        result[@"id"] = message[@"id"];
    }
    if (message[@"created_at"]) {
        result[@"created_at"] = message[@"created_at"];
    }
    return result;
}

- (void)sortAndReload {
    [self.messages sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSString *leftDate = left[@"created_at"] ?: @"";
        NSString *rightDate = right[@"created_at"] ?: @"";
        return [leftDate compare:rightDate];
    }];
    [self.tableView reloadData];
    self.stateLabel.text = self.messages.count ? nil : @"Напишите первое сообщение";
    [self scrollToBottomAnimated:NO];
    if (self.messages.count) {
        [[LumiAPI sharedClient] markChatRead:self.chatID];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (!self.messages.count) {
        return;
    }
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - Sending

- (void)sendTapped {
    [self sendCurrentText];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendCurrentText];
    return YES;
}

- (void)sendCurrentText {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || self.sending) {
        return;
    }
    self.inputField.text = @"";
    self.sending = YES;
    self.sendButton.enabled = NO;
    self.sendButton.alpha = 0.5;

    NSMutableDictionary *userMessage = [NSMutableDictionary dictionary];
    userMessage[@"content"] = text;
    userMessage[@"is_user"] = @YES;
    userMessage[@"pending"] = @YES;
    [self.messages addObject:userMessage];

    NSMutableDictionary *assistantMessage = [NSMutableDictionary dictionary];
    assistantMessage[@"content"] = @"";
    assistantMessage[@"is_user"] = @NO;
    assistantMessage[@"pending"] = @YES;
    [self.messages addObject:assistantMessage];
    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];

    __weak typeof(self) weakSelf = self;
    self.stream = [[LumiAPI sharedClient] sendMessage:text
                                              chatID:self.chatID
                                        eventHandler:^(NSString *type, NSDictionary *payload) {
        [weakSelf handleStreamEvent:type payload:payload];
    } completion:^(NSError *error) {
        [weakSelf finishStreamingWithError:error];
    }];
}

- (void)handleStreamEvent:(NSString *)type payload:(NSDictionary *)payload {
    if ([type isEqualToString:@"user_message"] || [type isEqualToString:@"user_message_updated"]) {
        NSDictionary *message = payload[@"message"] ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (normalized) {
            normalized[@"is_user"] = @YES;
            for (NSUInteger index = self.messages.count; index > 0; index--) {
                NSDictionary *existing = self.messages[index - 1];
                if ([existing[@"is_user"] boolValue] && [existing[@"pending"] boolValue]) {
                    [self.messages replaceObjectAtIndex:index - 1 withObject:normalized];
                    break;
                }
            }
            [self.tableView reloadData];
        }
        return;
    }
    if ([type isEqualToString:@"delta"]) {
        NSString *content = payload[@"content"];
        if ([content isKindOfClass:[NSString class]]) {
            NSMutableDictionary *assistant = [self pendingAssistantMessage];
            if (assistant) {
                NSString *existing = assistant[@"content"] ?: @"";
                assistant[@"content"] = [existing stringByAppendingString:content];
                [self reloadLastRows];
            }
        }
        return;
    }
    if ([type isEqualToString:@"intro_message"]) {
        NSDictionary *message = payload[@"message"] ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (normalized) {
            [self.messages addObject:normalized];
            [self.tableView reloadData];
            [self scrollToBottomAnimated:YES];
        }
        return;
    }
    if ([type isEqualToString:@"done"] || [type isEqualToString:@"variant_done"]) {
        NSDictionary *message = payload[@"message"] ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (!normalized) {
            return;
        }
        NSMutableDictionary *assistant = [self pendingAssistantMessage];
        if (assistant) {
            if (![normalized[@"content"] length] && [assistant[@"content"] length]) {
                normalized[@"content"] = assistant[@"content"];
            }
            NSUInteger index = [self.messages indexOfObjectIdenticalTo:assistant];
            if (index != NSNotFound) {
                [self.messages replaceObjectAtIndex:index withObject:normalized];
            } else {
                [self.messages addObject:normalized];
            }
        } else {
            [self.messages addObject:normalized];
        }
        [self.tableView reloadData];
        [self scrollToBottomAnimated:YES];
        return;
    }
    if ([type isEqualToString:@"error"]) {
        NSString *message = payload[@"error"];
        [self finishStreamingWithError:[NSError errorWithDomain:LumiAPIErrorDomain
                                                          code:500
                                                      userInfo:@{NSLocalizedDescriptionKey: message ?: @"Ошибка генерации"}]];
    }
}

- (NSMutableDictionary *)pendingAssistantMessage {
    for (NSUInteger index = self.messages.count; index > 0; index--) {
        NSMutableDictionary *message = self.messages[index - 1];
        if (![message[@"is_user"] boolValue] && [message[@"pending"] boolValue]) {
            return message;
        }
    }
    return nil;
}

- (void)reloadLastRows {
    NSInteger count = self.messages.count;
    if (count <= 0) {
        return;
    }
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndex:(NSUInteger)(count - 1)];
    if (count >= 2) {
        [indexes addIndex:(NSUInteger)(count - 2)];
    }
    [self.tableView reloadRowsAtIndexPaths:[self indexPathsFromIndexSet:indexes]
                          withRowAnimation:UITableViewRowAnimationNone];
    [self scrollToBottomAnimated:NO];
}

- (NSArray<NSIndexPath *> *)indexPathsFromIndexSet:(NSIndexSet *)set {
    NSMutableArray *paths = [NSMutableArray array];
    [set enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]];
    }];
    return paths;
}

- (void)finishStreamingWithError:(NSError *)error {
    self.sending = NO;
    self.sendButton.enabled = YES;
    self.sendButton.alpha = 1.0;
    for (NSMutableDictionary *message in self.messages) {
        if ([message[@"pending"] boolValue]) {
            message[@"pending"] = @NO;
            if (![message[@"content"] length] && ![message[@"is_user"] boolValue]) {
                message[@"content"] = error ? (error.localizedDescription ?: @"Не удалось получить ответ") : @"";
            }
        }
    }
    [self.tableView reloadData];
    [self scrollToBottomAnimated:YES];
}

#pragma mark - Keyboard

- (void)keyboardWillChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    self.inputBottomConstraint.constant = -MAX(0.0, overlap - self.view.safeAreaInsets.bottom);
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
    [self scrollToBottomAnimated:YES];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.inputBottomConstraint.constant = 0.0;
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LumiMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:indexPath];
    NSDictionary *message = self.messages[indexPath.row];
    BOOL isUser = [message[@"is_user"] boolValue];
    BOOL pending = [message[@"pending"] boolValue];
    [cell configureWithText:message[@"content"] isUser:isUser pending:pending];
    return cell;
}

@end
