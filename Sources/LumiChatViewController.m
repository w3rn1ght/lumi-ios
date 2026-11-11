#import "LumiChatViewController.h"
#import "LumiAPI.h"
#import <math.h>
#import "LumiCatalogStore.h"
#import "LumiImageLoader.h"
#import "LumiRichText.h"
#import "LumiSafe.h"
#import "LumiDiagnostics.h"
#import "LumiTheme.h"

#pragma mark - Photo view

static NSCache<NSString *, NSNumber *> *LumiPhotoRatioCache(void) {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 400;
    });
    return cache;
}

static NSNumber *LumiCachedPhotoRatio(NSString *url) {
    if (!url.length) {
        return nil;
    }
    NSNumber *cached = [LumiPhotoRatioCache() objectForKey:url];
    if (cached) {
        return cached;
    }
    UIImage *image = [[LumiImageLoader sharedLoader] cachedImageForURLString:url];
    if (image.size.width > 1.0 && image.size.height > 1.0) {
        NSNumber *ratio = @(image.size.height / image.size.width);
        [LumiPhotoRatioCache() setObject:ratio forKey:url];
        return ratio;
    }
    return nil;
}

/// Height that keeps the original aspect ratio. A generous cap keeps a very
/// tall image from filling the whole screen; `ScaleAspectFit` means the picture
/// is never cropped or stretched, only letterboxed in the worst case.
static CGFloat LumiPhotoHeightForRatio(CGFloat ratio, CGFloat width) {
    if (!isfinite(ratio) || ratio <= 0.02) {
        ratio = 0.75;
    }
    CGFloat height = width * ratio;
    return MIN(MAX(height, 96.0), 420.0);
}

@interface LumiPhotoView : UIImageView
@property (nonatomic, copy, nullable) NSString *photoURL;
@property (nonatomic, copy, nullable) void (^imageSizeHandler)(CGSize size);
@end

@implementation LumiPhotoView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        // Fit, never fill: cropped portraits were the "обрезанные" complaint.
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 12.0;
        self.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
        self.userInteractionEnabled = YES;
    }
    return self;
}

- (void)setPhotoURL:(NSString *)photoURL {
    if (_photoURL.length && [photoURL isEqualToString:_photoURL]) {
        return;
    }
    _photoURL = [photoURL copy];
    self.image = nil;
    if (!photoURL.length) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[LumiImageLoader sharedLoader] loadURLString:photoURL completion:^(UIImage *image) {
        LumiPhotoView *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.photoURL isEqualToString:photoURL]) {
            return;
        }
        strongSelf.image = image;
        if (image.size.width > 1.0 && image.size.height > 1.0 && strongSelf.imageSizeHandler) {
            strongSelf.imageSizeHandler(image.size);
        }
    }];
}

@end

#pragma mark - Message cell

@interface LumiMessageCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *bubbleLabel;
@property (nonatomic, strong) UIStackView *photoStack;
@property (nonatomic, strong) NSArray<LumiPhotoView *> *photoViews;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *photoHeightConstraints;
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *trailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *photoStackHeightConstraint;
@property (nonatomic, weak) UITableView *hostTableView;
@end

static const CGFloat kLumiPhotoCellHeight = 168.0;
static const NSUInteger kLumiPhotosPerMessage = 4;

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
        self.bubbleLabel.numberOfLines = 0;
        [self.bubble addSubview:self.bubbleLabel];

        self.photoStack = [[UIStackView alloc] init];
        self.photoStack.translatesAutoresizingMaskIntoConstraints = NO;
        self.photoStack.axis = UILayoutConstraintAxisVertical;
        self.photoStack.spacing = 6.0;
        self.photoStack.hidden = YES;
        [self.bubble addSubview:self.photoStack];

        NSMutableArray *views = [NSMutableArray array];
        NSMutableArray *heights = [NSMutableArray array];
        for (NSUInteger index = 0; index < kLumiPhotosPerMessage; index++) {
            LumiPhotoView *photo = [[LumiPhotoView alloc] initWithFrame:CGRectZero];
            NSLayoutConstraint *height = [photo.heightAnchor constraintEqualToConstant:kLumiPhotoCellHeight];
            height.active = YES;
            [heights addObject:height];
            [self.photoStack addArrangedSubview:photo];
            [views addObject:photo];
        }
        self.photoViews = views;
        self.photoHeightConstraints = heights;

        self.leadingConstraint = [self.bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0];
        self.trailingConstraint = [self.bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0];
        self.photoStackHeightConstraint = [self.photoStack.heightAnchor constraintEqualToConstant:0.0];

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:13.0],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-13.0],

            [self.photoStack.topAnchor constraintEqualToAnchor:self.bubbleLabel.bottomAnchor constant:6.0],
            [self.photoStack.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:8.0],
            [self.photoStack.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-8.0],
            [self.photoStack.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-8.0],
            self.photoStackHeightConstraint,
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.bubbleLabel.attributedText = nil;
    self.bubbleLabel.text = nil;
    for (NSUInteger index = 0; index < self.photoViews.count; index++) {
        LumiPhotoView *photo = self.photoViews[index];
        photo.imageSizeHandler = nil;
        photo.photoURL = nil;
        self.photoHeightConstraints[index].constant = kLumiPhotoCellHeight;
    }
    self.photoStack.hidden = YES;
    self.photoStackHeightConstraint.constant = 0.0;
}

- (void)updatePhotoStackHeight {
    CGFloat total = 0.0;
    NSUInteger visible = 0;
    for (NSUInteger index = 0; index < self.photoViews.count; index++) {
        if (self.photoViews[index].hidden) {
            continue;
        }
        total += self.photoHeightConstraints[index].constant;
        visible += 1;
    }
    if (visible == 0) {
        self.photoStack.hidden = YES;
        self.photoStackHeightConstraint.constant = 0.0;
        return;
    }
    self.photoStack.hidden = NO;
    self.photoStackHeightConstraint.constant = total + (visible - 1) * 6.0;
}

- (void)configureWithText:(NSString *)text
                   isUser:(BOOL)isUser
                  pending:(BOOL)pending
                photoURLs:(NSArray<NSString *> *)photoURLs {
    UIColor *textColor = isUser ? [UIColor whiteColor] : LumiTextColor();
    UIFont *baseFont = LumiFont(15.0, UIFontWeightRegular);
    NSString *displayText = text.length ? text : (pending ? @"…" : @"");
    NSString *visible = [LumiRichTextRenderer stringByStrippingImageMarkers:displayText] ?: @"";
    self.bubbleLabel.attributedText = [LumiRichTextRenderer attributedStringForText:visible
                                                                         textColor:textColor
                                                                          baseFont:baseFont
                                                                 prefixCommandName:@"**"];
    self.bubbleLabel.hidden = visible.length == 0 && photoURLs.count == 0;

    self.bubble.backgroundColor = isUser ? LumiAccentColor() : LumiSurfaceColor();
    self.leadingConstraint.active = !isUser;
    self.trailingConstraint.active = isUser;

    CGFloat contentWidth = CGRectGetWidth(self.contentView.bounds);
    if (contentWidth < 120.0) {
        contentWidth = CGRectGetWidth(self.hostTableView.bounds);
    }
    if (contentWidth < 120.0) {
        contentWidth = CGRectGetWidth([UIScreen mainScreen].bounds);
    }
    CGFloat photoWidth = MAX(140.0, contentWidth * 0.82 - 16.0);

    NSUInteger count = MIN(photoURLs.count, kLumiPhotosPerMessage);
    __weak typeof(self) weakSelf = self;
    for (NSUInteger index = 0; index < self.photoViews.count; index++) {
        LumiPhotoView *photo = self.photoViews[index];
        BOOL used = index < count;
        photo.hidden = !used;
        if (!used) {
            photo.imageSizeHandler = nil;
            photo.photoURL = nil;
            self.photoHeightConstraints[index].constant = kLumiPhotoCellHeight;
            continue;
        }

        NSString *url = photoURLs[index];
        NSNumber *knownRatio = LumiCachedPhotoRatio(url);
        self.photoHeightConstraints[index].constant = knownRatio
            ? LumiPhotoHeightForRatio(knownRatio.doubleValue, photoWidth)
            : kLumiPhotoCellHeight;

        photo.imageSizeHandler = ^(CGSize size) {
            if (size.width < 1.0 || size.height < 1.0) {
                return;
            }
            CGFloat ratio = size.height / size.width;
            [LumiPhotoRatioCache() setObject:@(ratio) forKey:url];
            dispatch_async(dispatch_get_main_queue(), ^{
                LumiMessageCell *cell = weakSelf;
                if (!cell || index >= cell.photoViews.count) {
                    return;
                }
                LumiPhotoView *current = cell.photoViews[index];
                if (![current.photoURL isEqualToString:url]) {
                    return;
                }
                CGFloat newHeight = LumiPhotoHeightForRatio(ratio, photoWidth);
                NSLayoutConstraint *constraint = cell.photoHeightConstraints[index];
                if (fabs(constraint.constant - newHeight) < 1.0) {
                    return;
                }
                constraint.constant = newHeight;
                [cell updatePhotoStackHeight];
                UITableView *table = cell.hostTableView;
                if (table.window) {
                    [UIView performWithoutAnimation:^{
                        [table beginUpdates];
                        [table endUpdates];
                    }];
                }
            });
        };
        photo.photoURL = url;
    }
    [self updatePhotoStackHeight];
}

@end

#pragma mark - Chat

static NSArray<NSString *> *LumiPhotoURLsInMessage(NSDictionary *message, NSString *content) {
    NSMutableOrderedSet *urls = [NSMutableOrderedSet orderedSet];

    void (^addIfURL)(id) = ^(id value) {
        NSString *string = LumiStringValue(value);
        if (string.length && ([string hasPrefix:@"http://"] || [string hasPrefix:@"https://"])) {
            [urls addObject:string];
        }
    };

    for (NSString *key in @[@"image_url", @"photo_url", @"image", @"photo", @"media_url", @"attachment_url"]) {
        addIfURL(LumiValue(message, key));
    }
    for (NSString *key in @[@"attachments", @"photos", @"images", @"media", @"files"]) {
        NSArray *items = LumiAsArray(LumiValue(message, key));
        for (id item in items) {
            if ([item isKindOfClass:[NSString class]]) {
                addIfURL(item);
                continue;
            }
            NSDictionary *dictionary = LumiAsDictionary(item);
            if (!dictionary) {
                continue;
            }
            NSString *kind = [LumiAsString(LumiValue(dictionary, @"type"))
                              ?: LumiAsString(LumiValue(dictionary, @"kind")) lowercaseString];
            if (kind.length && !([kind containsString:@"image"] || [kind containsString:@"photo"] ||
                                 [kind containsString:@"gif"] || [kind containsString:@"webp"])) {
                continue;
            }
            addIfURL(LumiValue(dictionary, @"url"));
            addIfURL(LumiValue(dictionary, @"src"));
            addIfURL(LumiValue(dictionary, @"photo_url"));
            addIfURL(LumiValue(dictionary, @"file_url"));
            if (!kind.length && !LumiAsString(LumiValue(dictionary, @"url")).length) {
                addIfURL(LumiValue(dictionary, @"id"));
            }
        }
    }
    for (NSString *url in [LumiRichTextRenderer imageURLsInText:content]) {
        [urls addObject:url];
    }
    return urls.array;
}

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
        NSDictionary *safeItem = LumiAsDictionary(item) ?: @{};
        if (kind == LumiDetailKindStory) {
            _chatTitle = LumiAsString(safeItem[@"title"]) ?: LumiAsString(_chat[@"title"]);
        } else {
            _chatTitle = LumiAsString(safeItem[@"name"]) ?: LumiAsString(_chat[@"title"]);
        }
        _avatarURL = LumiAsString(safeItem[@"avatar_url"]);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    [self refreshNavigationTitle];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.contentInset = UIEdgeInsetsMake(10.0, 0, 10.0, 0);
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
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

    [LumiDiagnostics log:@"чат %@: открыт (%@), сообщений в списке: %lu",
     self.chatID, self.chatTitle ?: @"без названия", (unsigned long)self.messages.count];
    [self loadMessages];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.stream cancel];
}

- (void)refreshNavigationTitle {
    NSString *name = self.chatTitle.length ? self.chatTitle : @"";
    if (self.chatNumber > 0) {
        self.title = [NSString stringWithFormat:@"%@ · чат №%lu", name, (unsigned long)self.chatNumber];
    } else {
        self.title = name;
    }
}

#pragma mark - Chat parsing

- (NSString *)chatIdentifierFromChat:(NSDictionary *)chat {
    for (NSString *key in @[@"id", @"chat_id", @"session_id"]) {
        NSString *value = LumiAsString(LumiValue(chat, key));
        if (value.length) {
            return value;
        }
    }
    return nil;
}

- (NSDictionary *)normalizedChat:(NSDictionary *)chat {
    NSDictionary *dictionary = LumiAsDictionary(chat);
    if (!dictionary) {
        return @{};
    }
    NSMutableDictionary *result = [dictionary mutableCopy];
    NSDictionary *nested = LumiAsDictionary(LumiValue(dictionary, @"chat"));
    if (nested) {
        if (!LumiAsString(result[@"title"]).length) {
            NSString *title = LumiAsString(nested[@"title"]) ?: LumiNestedString(nested, @"target", @"name");
            if (title.length) {
                result[@"title"] = title;
            }
        }
        return result;
    }
    NSDictionary *target = LumiAsDictionary(LumiValue(dictionary, @"target"));
    if (target) {
        NSString *title = LumiAsString(result[@"title"]) ?: LumiAsString(target[@"name"]);
        if (title.length) {
            result[@"title"] = title;
        }
        NSString *avatar = LumiAsString(result[@"avatar_url"]) ?: LumiAsString(target[@"avatar_url"]);
        if (avatar.length) {
            result[@"avatar_url"] = avatar;
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
            [LumiDiagnostics log:@"чат %@: история не загрузилась — %@", weakSelf.chatID, error.localizedDescription];
            return;
        }
        NSDictionary *dictionary = LumiAsDictionary(result) ?: @{};
        NSArray *rawMessages = LumiAsArray(dictionary[@"messages"]);
        weakSelf.hasMore = [LumiAsNumber(dictionary[@"has_more"]) boolValue];
        [weakSelf applyChatMetadataFromPayload:dictionary];
        [weakSelf applyMessages:rawMessages];
        if (!weakSelf.messages.count) {
            [weakSelf seedIntroIfNeeded];
            return;
        }
        [weakSelf sortAndReload];
        [[LumiAPI sharedClient] markChatRead:weakSelf.chatID];
    }];
}

- (void)applyChatMetadataFromPayload:(NSDictionary *)payload {
    NSDictionary *chat = LumiAsDictionary(LumiValue(payload, @"chat"));
    if (!chat) {
        chat = LumiAsDictionary(LumiValue(payload, @"session"));
    }
    if (!chat) {
        return;
    }
    NSString *title = LumiAsString(chat[@"title"]);
    if (!title.length) {
        title = LumiNestedString(chat, @"target", @"name");
    }
    if (title.length) {
        self.chatTitle = title;
        [self refreshNavigationTitle];
    }
    NSString *avatar = LumiAsString(chat[@"avatar_url"]) ?: LumiNestedString(chat, @"target", @"avatar_url");
    if (avatar.length) {
        self.avatarURL = avatar;
    }
}

- (void)applyMessages:(NSArray *)rawMessages {
    [self.messages removeAllObjects];
    NSArray *messages = LumiAsArray(rawMessages);
    if (!messages) {
        return;
    }
    for (id message in messages) {
        NSMutableDictionary *normalized = [self normalizedMessage:LumiAsDictionary(message)];
        if (normalized) {
            [self.messages addObject:normalized];
        }
    }
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
        [weakSelf applyChatMetadataFromPayload:dictionary];
        [weakSelf applyMessages:dictionary[@"messages"]];
        [weakSelf sortAndReload];
    }];
}

- (NSMutableDictionary *)normalizedMessage:(NSDictionary *)message {
    if (![message isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *content = LumiStringValue(LumiValue(message, @"content"))
        ?: LumiStringValue(LumiValue(message, @"text"))
        ?: LumiStringValue(LumiValue(message, @"message"))
        ?: @"";
    BOOL isUser = NO;
    NSString *role = LumiStringValue(LumiValue(message, @"role"))
        ?: LumiStringValue(LumiValue(message, @"sender"))
        ?: LumiStringValue(LumiValue(message, @"author"))
        ?: LumiStringValue(LumiValue(message, @"sender_type"));
    if (role.length) {
        isUser = [role isEqualToString:@"user"] || [role isEqualToString:@"human"];
    }
    NSNumber *isUserFlag = LumiAsNumber(LumiValue(message, @"is_user"));
    if (isUserFlag) {
        isUser = isUserFlag.boolValue;
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"content"] = content;
    result[@"is_user"] = @(isUser);
    NSString *identifier = LumiStringValue(LumiValue(message, @"id"));
    if (identifier.length) {
        result[@"id"] = identifier;
    }
    NSString *createdAt = LumiStringValue(LumiValue(message, @"created_at"))
        ?: LumiStringValue(LumiValue(message, @"createdAt"))
        ?: LumiStringValue(LumiValue(message, @"timestamp"));
    if (createdAt.length) {
        result[@"created_at"] = createdAt;
    }
    NSArray<NSString *> *photos = LumiPhotoURLsInMessage(message, content);
    if (photos.count) {
        result[@"photo_urls"] = photos;
    }
    return result;
}

- (void)sortAndReload {
    [self.messages sortUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
        NSDictionary *left = LumiAsDictionary(leftObject);
        NSDictionary *right = LumiAsDictionary(rightObject);
        return LumiCompareDates(LumiValue(left, @"created_at"), LumiValue(right, @"created_at"));
    }];
    [self safeReloadTable];
    self.stateLabel.text = self.messages.count ? nil : @"Напишите первое сообщение";
    [self scrollToBottomAnimated:NO];
    if (self.messages.count) {
        [[LumiAPI sharedClient] markChatRead:self.chatID];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (!self.messages.count || self.tableView.numberOfSections == 0) {
        return;
    }
    NSInteger rows = [self.tableView numberOfRowsInSection:0];
    if (rows <= 0) {
        return;
    }
    NSInteger row = MIN((NSInteger)self.messages.count, rows) - 1;
    if (row < 0) {
        return;
    }
    @try {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                              atScrollPosition:UITableViewScrollPositionBottom
                                      animated:animated];
    } @catch (NSException *exception) {
        NSLog(@"[Lumi] scroll failed: %@", exception.reason);
    }
}

/// All table mutations funnel through here so a stale row index can never
/// terminate the app with NSInternalInconsistencyException.
- (void)safeReloadTable {
    @try {
        [self.tableView reloadData];
    } @catch (NSException *exception) {
        NSLog(@"[Lumi] reloadData failed: %@", exception.reason);
    }
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
    NSString *text = [(self.inputField.text ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
        NSDictionary *message = LumiAsDictionary(LumiValue(payload, @"message")) ?: payload;
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
            [self reloadAllRows];
        }
        return;
    }
    if ([type isEqualToString:@"delta"]) {
        NSString *content = LumiStringValue(LumiValue(payload, @"content"));
        if (content.length) {
            NSMutableDictionary *assistant = [self pendingAssistantMessage];
            if (assistant) {
                NSString *existing = LumiAsString(assistant[@"content"]) ?: @"";
                NSString *combined = [existing stringByAppendingString:content];
                assistant[@"content"] = combined;
                NSArray *photos = LumiPhotoURLsInMessage(@{}, combined);
                assistant[@"photo_urls"] = photos.count ? photos : nil;
                [self reloadLastRows];
            }
        }
        return;
    }
    if ([type isEqualToString:@"intro_message"]) {
        NSDictionary *message = LumiAsDictionary(LumiValue(payload, @"message")) ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (normalized) {
            [self.messages addObject:normalized];
            [self reloadAllRows];
            [self scrollToBottomAnimated:YES];
        }
        return;
    }
    if ([type isEqualToString:@"done"] || [type isEqualToString:@"variant_done"]) {
        NSDictionary *message = LumiAsDictionary(LumiValue(payload, @"message")) ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (!normalized) {
            return;
        }
        NSMutableDictionary *assistant = [self pendingAssistantMessage];
        if (assistant) {
            if (![LumiAsString(normalized[@"content"]) length] && [LumiAsString(assistant[@"content"]) length]) {
                normalized[@"content"] = assistant[@"content"];
            }
            if (!LumiAsArray(normalized[@"photo_urls"]).count && LumiAsArray(assistant[@"photo_urls"]).count) {
                normalized[@"photo_urls"] = assistant[@"photo_urls"];
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
        [self reloadAllRows];
        [self scrollToBottomAnimated:YES];
        return;
    }
    if ([type isEqualToString:@"error"]) {
        NSString *message = LumiStringValue(LumiValue(payload, @"error")) ?: LumiStringValue(LumiValue(payload, @"message"));
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
    NSMutableSet *paths = [NSMutableSet set];
    [paths addObject:[NSIndexPath indexPathForRow:count - 1 inSection:0]];
    if (count >= 2) {
        [paths addObject:[NSIndexPath indexPathForRow:count - 2 inSection:0]];
    }
    [self safeReloadRows:paths];
    [self scrollToBottomAnimated:NO];
}

/// Row-count-safe reload used while streaming: any mismatch is resolved by a
/// full reload inside an update transaction.
- (void)reloadAllRows {
    if (self.tableView.numberOfSections == 0) {
        [self safeReloadTable];
        return;
    }
    NSInteger expected = [self.tableView numberOfRowsInSection:0];
    if (expected != (NSInteger)self.messages.count) {
        [self safeReloadTable];
        return;
    }
    @try {
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    } @catch (NSException *exception) {
        NSLog(@"[Lumi] batch update failed: %@", exception.reason);
        [self safeReloadTable];
    }
}

/// Reloading rows that disappeared (e.g. the server replaced a placeholder)
/// throws an NSInternalInconsistencyException — reload the table instead.
- (void)safeReloadRows:(NSSet<NSIndexPath *> *)indexPaths {
    if (!indexPaths.count) {
        return;
    }
    if (self.tableView.numberOfSections == 0) {
        [self safeReloadTable];
        return;
    }
    NSInteger rows = [self.tableView numberOfRowsInSection:0];
    NSInteger expected = (NSInteger)self.messages.count;
    for (NSIndexPath *path in indexPaths) {
        if (path.row >= rows || path.row < 0 || path.row >= expected) {
            [self safeReloadTable];
            return;
        }
    }
    @try {
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:indexPaths.allObjects
                              withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    } @catch (NSException *exception) {
        NSLog(@"[Lumi] reloadRows failed: %@", exception.reason);
        [self safeReloadTable];
    }
}

- (void)finishStreamingWithError:(NSError *)error {
    self.sending = NO;
    self.sendButton.enabled = YES;
    self.sendButton.alpha = 1.0;
    NSMutableSet *affected = [NSMutableSet set];
    NSUInteger index = 0;
    for (NSMutableDictionary *message in self.messages) {
        if ([message[@"pending"] boolValue]) {
            message[@"pending"] = @NO;
            if (![message[@"content"] length] && ![message[@"is_user"] boolValue]) {
                message[@"content"] = error ? (error.localizedDescription ?: @"Не удалось получить ответ") : @"";
            }
            [affected addObject:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]];
        }
        index++;
    }
    [self safeReloadRows:affected];
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
    cell.hostTableView = tableView;
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.messages.count) {
        [cell configureWithText:@"" isUser:NO pending:NO photoURLs:@[]];
        return cell;
    }
    NSDictionary *message = self.messages[indexPath.row];
    BOOL isUser = [message[@"is_user"] boolValue];
    BOOL pending = [message[@"pending"] boolValue];
    [cell configureWithText:LumiStringValue(message[@"content"])
                     isUser:isUser
                    pending:pending
                  photoURLs:LumiAsArray(message[@"photo_urls"]) ?: @[]];
    return cell;
}

@end
