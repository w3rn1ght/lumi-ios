#import "LumiChatViewController.h"
#import "LumiAPIClient.h"
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

        self.leadingConstraint = [self.bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0];
        self.trailingConstraint = [self.bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0];

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.80],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.bubbleLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-10.0],
            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:13.0],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-13.0],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text isUser:(BOOL)isUser {
    self.bubbleLabel.text = text;
    self.bubble.backgroundColor = isUser ? LumiAccentColor() : LumiSurfaceColor();
    self.bubbleLabel.textColor = isUser ? [UIColor whiteColor] : LumiTextColor();
    self.leadingConstraint.active = !isUser;
    self.trailingConstraint.active = isUser;
}

@end

@interface LumiChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSLayoutConstraint *inputBottomConstraint;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *messages;
@property (nonatomic, assign) BOOL sending;
@end

@implementation LumiChatViewController

- (instancetype)initWithSessionID:(NSString *)sessionID title:(NSString *)title {
    self = [super init];
    if (self) {
        _sessionID = [sessionID copy];
        _chatTitle = [title copy];
        _messages = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = self.chatTitle.length ? self.chatTitle : @"Чат";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.estimatedRowHeight = 56.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(10, 0, 10, 0);
    [self.tableView registerClass:[LumiMessageCell class] forCellReuseIdentifier:@"message"];
    [self.view addSubview:self.tableView];

    self.inputBar = [[UIView alloc] init];
    self.inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputBar.backgroundColor = LumiSurfaceColor();
    [self.view addSubview:self.inputBar];

    self.inputField = LumiTextField(@"Сообщение");
    self.inputField.backgroundColor = LumiElevatedColor();
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    [self.inputBar addSubview:self.inputField];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton setTitle:@"↑" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = LumiFont(20.0, UIFontWeightBold);
    self.sendButton.backgroundColor = LumiAccentColor();
    self.sendButton.layer.cornerRadius = 22.0;
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.sendButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.textColor = LumiMutedColor();
    self.stateLabel.font = LumiFont(14.0, UIFontWeightRegular);
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.numberOfLines = 0;
    self.stateLabel.hidden = YES;
    [self.view addSubview:self.stateLabel];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    self.inputBottomConstraint = [self.inputBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottomConstraint,

        [self.inputField.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:12.0],
        [self.inputField.topAnchor constraintEqualToAnchor:self.inputBar.topAnchor constant:8.0],
        [self.inputField.bottomAnchor constraintEqualToAnchor:self.inputBar.bottomAnchor constant:-8.0],
        [self.inputField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-8.0],

        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-12.0],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.inputBar.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:44.0],
        [self.sendButton.heightAnchor constraintEqualToConstant:44.0],

        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.stateLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.stateLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:32.0],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-32.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    [self loadMessages];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillChange:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = MAX(0.0, CGRectGetHeight(self.view.bounds) - [self.view convertRect:frame fromView:nil].origin.y);
    self.inputBottomConstraint.constant = -MAX(0.0, overlap - self.view.safeAreaInsets.bottom);
    [self.view layoutIfNeeded];
}

- (NSString *)textFromValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [self textFromValue:(value[@"content"] ?: value[@"text"] ?: value[@"message"])];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableString *result = [NSMutableString string];
        for (id item in value) {
            NSString *text = [self textFromValue:item];
            if (text.length) {
                [result appendString:text];
            }
        }
        return result;
    }
    return nil;
}

- (void)normalizeMessagesFromJSON:(NSDictionary *)json {
    NSArray *raw = json[@"results"];
    if (![raw isKindOfClass:[NSArray class]]) raw = json[@"messages"];
    if (![raw isKindOfClass:[NSArray class]]) raw = json[@"data"];
    if (![raw isKindOfClass:[NSArray class]]) raw = @[];

    NSMutableArray *normalized = [NSMutableArray array];
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *message = item;
        NSString *role = message[@"role"] ?: message[@"sender"] ?: message[@"author"];
        if ([role isKindOfClass:[NSDictionary class]]) {
            role = ((NSDictionary *)role)[@"role"];
        }
        if ([message[@"is_user"] boolValue]) {
            role = @"user";
        }
        BOOL isUser = [role isEqual:@"user"] || [role isEqual:@"human"];
        NSString *text = [self textFromValue:(message[@"content"] ?: message[@"text"] ?: message[@"message"])];
        if (!text.length) {
            continue;
        }
        [normalized addObject:@{@"text": text, @"user": @(isUser)}];
    }
    self.messages = normalized;
    [self.tableView reloadData];
    if (normalized.count) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:normalized.count - 1 inSection:0]
                              atScrollPosition:UITableViewScrollPositionBottom
                                      animated:NO];
    }
}

- (void)loadMessages {
    [self.spinner startAnimating];
    [[LumiAPIClient sharedClient] fetchMessagesForSession:self.sessionID
                                               completion:^(NSDictionary *json, NSError *error) {
        [self.spinner stopAnimating];
        if (error) {
            self.stateLabel.text = [NSString stringWithFormat:@"Не удалось загрузить сообщения.\n%@", error.localizedDescription];
            self.stateLabel.hidden = NO;
            return;
        }
        self.stateLabel.hidden = YES;
        [self normalizeMessagesFromJSON:json];
    }];
}

- (void)sendTapped {
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || self.sending) {
        return;
    }
    self.sending = YES;
    self.inputField.text = @"";
    [self.messages addObject:@{@"text": text, @"user": @YES}];
    [self.tableView reloadData];
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom
                                  animated:YES];

    [[LumiAPIClient sharedClient] sendMessage:text
                                    sessionID:self.sessionID
                                       turnID:nil
                                       stepID:nil
                                   completion:^(NSDictionary *json, NSError *error) {
        self.sending = NO;
        if (error) {
            [self showTypingError:error.localizedDescription];
            return;
        }
        NSString *reply = [self textFromValue:(json[@"reply"] ?: json[@"content"] ?: json[@"message"] ?: json[@"text"])];
        if (reply.length) {
            [self.messages addObject:@{@"text": reply, @"user": @NO}];
            [self.tableView reloadData];
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0]
                                  atScrollPosition:UITableViewScrollPositionBottom
                                          animated:YES];
        } else {
            [self pollForReplyAttempt:0 previousCount:self.messages.count];
        }
    }];
}

- (void)pollForReplyAttempt:(NSInteger)attempt previousCount:(NSUInteger)previousCount {
    if (attempt >= 10) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[LumiAPIClient sharedClient] fetchMessagesForSession:self.sessionID
                                                   completion:^(NSDictionary *json, NSError *error) {
            if (error) {
                [self pollForReplyAttempt:attempt + 1 previousCount:previousCount];
                return;
            }
            NSArray *before = self.messages;
            [self normalizeMessagesFromJSON:json];
            if (self.messages.count <= before.count) {
                [self pollForReplyAttempt:attempt + 1 previousCount:previousCount];
            }
        }];
    });
}

- (void)showTypingError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Сообщение не отправлено"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LumiMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:indexPath];
    NSDictionary *message = self.messages[indexPath.row];
    [cell configureWithText:message[@"text"] isUser:[message[@"user"] boolValue]];
    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return YES;
}

@end
