#import "LumiChatViewController.h"
#import "LumiAPI.h"
#import <math.h>
#import "LumiCatalogStore.h"
#import "LumiChatAppearance.h"
#import "LumiChatInfoViewController.h"
#import "LumiImageLoader.h"
#import "LumiImageViewerViewController.h"
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

/// `**Кума** улыбается` -> "Кума". Used to find the speaker's avatar in the
/// catalog for story chats with several characters.
static NSString *LumiSpeakerKey(NSString *name) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@":;,.!?—–-«»\"' \t"];
    while (trimmed.length && [trailing characterIsMember:[trimmed characterAtIndex:trimmed.length - 1]]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    return trimmed;
}

static NSString *LumiLeadingBoldName(NSString *text) {
    if (![text hasPrefix:@"**"] || text.length < 5) {
        return nil;
    }
    NSRange close = [text rangeOfString:@"**" options:0 range:NSMakeRange(2, text.length - 2)];
    if (close.location == NSNotFound || close.location == 2) {
        return nil;
    }
    NSString *name = LumiSpeakerKey([text substringWithRange:NSMakeRange(2, close.location - 2)]);
    return name.length ? name : nil;
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
@property (nonatomic, strong) NSLayoutConstraint *bubbleAfterAvatarConstraint;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) NSLayoutConstraint *photoStackHeightConstraint;
@property (nonatomic, strong) UIStackView *variantBar;
@property (nonatomic, strong) UIButton *variantPrevButton;
@property (nonatomic, strong) UIButton *variantNextButton;
@property (nonatomic, strong) UILabel *variantLabel;
@property (nonatomic, strong) NSLayoutConstraint *bubbleBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *variantBottomConstraint;
@property (nonatomic, weak) UITableView *hostTableView;
@property (nonatomic, copy, nullable) void (^longPressHandler)(void);
@property (nonatomic, copy, nullable) void (^avatarTapHandler)(void);
@property (nonatomic, copy, nullable) void (^variantStepHandler)(NSInteger delta);
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

        self.avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.avatarButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarButton.backgroundColor = LumiSurfaceColor();
        self.avatarButton.layer.cornerRadius = 16.0;
        self.avatarButton.clipsToBounds = YES;
        self.avatarButton.hidden = YES;
        [self.avatarButton addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:self.avatarButton];

        // NOTE: never load remote images into UIButton.imageView — the button
        // resets it on every layout pass. A dedicated subview keeps the image.
        self.avatarImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        self.avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.avatarImageView.clipsToBounds = YES;
        self.avatarImageView.userInteractionEnabled = NO;
        self.avatarImageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
        [self.avatarButton addSubview:self.avatarImageView];
        [NSLayoutConstraint activateConstraints:@[
            [self.avatarImageView.topAnchor constraintEqualToAnchor:self.avatarButton.topAnchor],
            [self.avatarImageView.leadingAnchor constraintEqualToAnchor:self.avatarButton.leadingAnchor],
            [self.avatarImageView.trailingAnchor constraintEqualToAnchor:self.avatarButton.trailingAnchor],
            [self.avatarImageView.bottomAnchor constraintEqualToAnchor:self.avatarButton.bottomAnchor],
        ]];

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

        self.variantBar = [[UIStackView alloc] init];
        self.variantBar.translatesAutoresizingMaskIntoConstraints = NO;
        self.variantBar.axis = UILayoutConstraintAxisHorizontal;
        self.variantBar.spacing = 4.0;
        self.variantBar.alignment = UIStackViewAlignmentCenter;
        self.variantBar.hidden = YES;
        [self.contentView addSubview:self.variantBar];

        self.variantPrevButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.variantPrevButton setTitle:@"‹" forState:UIControlStateNormal];
        self.variantPrevButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        [self.variantPrevButton setTitleColor:LumiAccentColor() forState:UIControlStateNormal];
        [self.variantPrevButton addTarget:self action:@selector(variantPrevTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.variantPrevButton.widthAnchor constraintEqualToConstant:24.0].active = YES;
        [self.variantPrevButton.heightAnchor constraintEqualToConstant:24.0].active = YES;

        self.variantLabel = [[UILabel alloc] init];
        self.variantLabel.font = LumiFont(11.0, UIFontWeightMedium);
        self.variantLabel.textColor = LumiMutedColor();
        self.variantLabel.textAlignment = NSTextAlignmentCenter;
        [self.variantLabel.widthAnchor constraintGreaterThanOrEqualToConstant:30.0].active = YES;

        self.variantNextButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.variantNextButton setTitle:@"›" forState:UIControlStateNormal];
        self.variantNextButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        [self.variantNextButton setTitleColor:LumiAccentColor() forState:UIControlStateNormal];
        [self.variantNextButton addTarget:self action:@selector(variantNextTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.variantNextButton.widthAnchor constraintEqualToConstant:24.0].active = YES;
        [self.variantNextButton.heightAnchor constraintEqualToConstant:24.0].active = YES;

        [self.variantBar addArrangedSubview:self.variantPrevButton];
        [self.variantBar addArrangedSubview:self.variantLabel];
        [self.variantBar addArrangedSubview:self.variantNextButton];

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.45;
        [self.contentView addGestureRecognizer:longPress];

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
        self.bubbleAfterAvatarConstraint = [self.bubble.leadingAnchor constraintEqualToAnchor:self.avatarButton.trailingAnchor constant:8.0];
        self.bubbleAfterAvatarConstraint.active = NO;
        self.photoStackHeightConstraint = [self.photoStack.heightAnchor constraintEqualToConstant:0.0];
        self.bubbleBottomConstraint = [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0];
        self.variantBottomConstraint = [self.variantBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0];
        self.variantBottomConstraint.active = NO;

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82],
            [self.bubble.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [self.bubbleLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.bubbleLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:13.0],
            [self.bubbleLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-13.0],

            [self.photoStack.topAnchor constraintEqualToAnchor:self.bubbleLabel.bottomAnchor constant:6.0],
            [self.photoStack.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:8.0],
            [self.photoStack.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-8.0],
            [self.photoStack.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-8.0],
            self.photoStackHeightConstraint,
            self.bubbleBottomConstraint,

            // The variant arrows live in the avatar gutter, directly under the
            // character icon, instead of hugging the bubble's left edge.
            [self.variantBar.topAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:4.0],
            [self.variantBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],

            [self.avatarButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
            [self.avatarButton.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:2.0],
            [self.avatarButton.widthAnchor constraintEqualToConstant:32.0],
            [self.avatarButton.heightAnchor constraintEqualToConstant:32.0],
            [self.avatarButton.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
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
    self.variantBar.hidden = YES;
    self.bubbleBottomConstraint.active = YES;
    self.variantBottomConstraint.active = NO;
    self.longPressHandler = nil;
    self.avatarTapHandler = nil;
    self.avatarButton.hidden = YES;
    self.avatarImageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    self.leadingConstraint.active = NO;
    self.trailingConstraint.active = NO;
    self.bubbleAfterAvatarConstraint.active = NO;
    self.variantStepHandler = nil;
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
                photoURLs:(NSArray<NSString *> *)photoURLs
            variantsCount:(NSInteger)variantsCount
              activeIndex:(NSInteger)activeIndex
                avatarURL:(NSString *)avatarURL
            speakerImages:(NSDictionary<NSString *, UIImage *> *)speakerImages {
    LumiChatAppearance *appearance = [LumiChatAppearance sharedAppearance];
    UIColor *textColor = isUser ? appearance.userTextColor : appearance.characterTextColor;
    UIFont *baseFont = LumiFont(15.0, UIFontWeightRegular);
    NSString *displayText = text.length ? text : (pending ? @"…" : @"");
    NSString *visible = [LumiRichTextRenderer stringByStrippingImageMarkers:displayText] ?: @"";
    self.bubbleLabel.attributedText = [LumiRichTextRenderer attributedStringForText:visible
                                                                          textColor:textColor
                                                                           baseFont:baseFont
                                                                          boldColor:appearance.boldColor
                                                                        italicColor:appearance.italicColor
                                                                      quoteTextColor:appearance.quoteTextColor
                                                                      quoteFillColor:appearance.quoteFillColor
                                                                       speakerImages:speakerImages];
    self.bubbleLabel.hidden = visible.length == 0 && photoURLs.count == 0;

    self.bubble.backgroundColor = isUser ? appearance.userBubbleColor : appearance.characterBubbleColor;

    BOOL showAvatar = !isUser && avatarURL.length > 0;
    self.avatarButton.hidden = !showAvatar;
    if (showAvatar) {
        [[LumiImageLoader sharedLoader] loadURLString:avatarURL intoImageView:self.avatarImageView];
    } else {
        self.avatarImageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    }
    self.leadingConstraint.active = !isUser && !showAvatar;
    self.bubbleAfterAvatarConstraint.active = !isUser && showAvatar;
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
                // Once per photo per message is enough; off-screen cells pick the
                // new height up on their next layout pass.
                if (table.window && [table indexPathForCell:cell]) {
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

    BOOL showVariants = !isUser && !pending && variantsCount > 1;
    self.variantBar.hidden = !showVariants;
    if (showVariants) {
        NSInteger safeIndex = MAX(0, MIN(activeIndex, variantsCount - 1));
        self.variantLabel.text = [NSString stringWithFormat:@"%ld/%ld",
                                  (long)(safeIndex + 1), (long)variantsCount];
        self.variantPrevButton.enabled = safeIndex > 0;
        self.variantNextButton.enabled = safeIndex < variantsCount - 1;
        self.variantPrevButton.alpha = safeIndex > 0 ? 1.0 : 0.3;
        self.variantNextButton.alpha = safeIndex < variantsCount - 1 ? 1.0 : 0.3;
    }
    if (showVariants != !self.variantBottomConstraint.active) {
        self.bubbleBottomConstraint.active = !showVariants;
        self.variantBottomConstraint.active = showVariants;
    }
}

- (void)variantPrevTapped {
    if (self.variantStepHandler) {
        self.variantStepHandler(-1);
    }
}

- (void)variantNextTapped {
    if (self.variantStepHandler) {
        self.variantStepHandler(1);
    }
}

- (void)avatarTapped {
    if (self.avatarTapHandler) {
        self.avatarTapHandler();
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && self.longPressHandler) {
        self.longPressHandler();
    }
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
@property (nonatomic, strong) NSDictionary *chatItem;
@property (nonatomic, assign) LumiDetailKind chatKind;
@property (nonatomic, copy) NSString *chatID;
@property (nonatomic, copy) NSString *chatTitle;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *photoButton;
@property (nonatomic, strong) UIButton *sparksButton;
@property (nonatomic, assign) NSInteger sparksBalance;
@property (nonatomic, assign) BOOL sparksKnown;
@property (nonatomic, copy, nullable) NSString *editingMessageID;
@property (nonatomic, copy, nullable) NSString *editingOriginalContent;
@property (nonatomic, assign) BOOL photoGenerating;
@property (nonatomic, assign) BOOL regenerating;
@property (nonatomic, strong, nullable) LumiChatStream *variantStream;
@property (nonatomic, strong) NSLayoutConstraint *inputBottomConstraint;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *messages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *speakerIndex;
@property (nonatomic, assign) BOOL speakerIndexBuilt;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *speakerImages;
@property (nonatomic, assign) BOOL speakerReloadScheduled;
@property (nonatomic, assign) BOOL speakerImageRetryScheduled;
@property (nonatomic, assign) NSUInteger speakerImageRetryRounds;
@property (nonatomic, assign) BOOL streamFlushScheduled;
@property (nonatomic, assign) NSUInteger streamFlushToken;
@property (nonatomic, assign) BOOL streamDirty;
@property (nonatomic, assign) BOOL uiActive;
@property (nonatomic, assign) BOOL readMarked;
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
        _chatItem = [item copy] ?: @{};
        _chatKind = kind;
        _messages = [NSMutableArray array];
        _speakerImages = [NSMutableDictionary dictionary];
        NSDictionary *safeItem = LumiAsDictionary(item) ?: @{};
        if (kind == LumiDetailKindStory) {
            _chatTitle = LumiAsString(safeItem[@"title"]) ?: LumiAsString(_chat[@"title"]);
        } else {
            _chatTitle = LumiAsString(safeItem[@"name"]) ?: LumiAsString(_chat[@"title"]);
        }
        _avatarURL = LumiAsString(safeItem[@"avatar_url"]);
        // Скрываем tab bar (Каталог/Чаты/Профиль) в экране чата
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    [self refreshNavigationTitle];

    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    [infoButton addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:infoButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyChatAppearance)
                                                 name:LumiChatAppearanceDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogUpdated)
                                                 name:LumiCatalogDidUpdateNotification
                                               object:nil];

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

    self.photoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.photoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.photoButton setTitle:@"📷" forState:UIControlStateNormal];
    self.photoButton.titleLabel.font = [UIFont systemFontOfSize:19.0];
    self.photoButton.backgroundColor = LumiElevatedColor();
    self.photoButton.layer.cornerRadius = 17.0;
    [self.photoButton addTarget:self action:@selector(photoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.photoButton];

    self.sparksButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sparksButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sparksButton setTitle:@"⚡ —" forState:UIControlStateNormal];
    self.sparksButton.titleLabel.font = LumiFont(12.0, UIFontWeightSemibold);
    [self.sparksButton setTitleColor:LumiAccentColor() forState:UIControlStateNormal];
    self.sparksButton.backgroundColor = LumiElevatedColor();
    self.sparksButton.layer.cornerRadius = 14.0;
    [self.sparksButton addTarget:self action:@selector(sparksTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.sparksButton];

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

        [self.inputField.leadingAnchor constraintEqualToAnchor:self.sparksButton.trailingAnchor constant:6.0],
        [self.inputField.centerYAnchor constraintEqualToAnchor:self.inputBar.centerYAnchor],
        [self.inputField.heightAnchor constraintEqualToConstant:38.0],
        [self.inputField.trailingAnchor constraintEqualToAnchor:self.photoButton.leadingAnchor constant:-6.0],

        [self.sparksButton.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:10.0],
        [self.sparksButton.centerYAnchor constraintEqualToAnchor:self.inputBar.centerYAnchor],
        [self.sparksButton.widthAnchor constraintEqualToConstant:52.0],
        [self.sparksButton.heightAnchor constraintEqualToConstant:28.0],

        [self.photoButton.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-6.0],
        [self.photoButton.centerYAnchor constraintEqualToAnchor:self.inputBar.centerYAnchor],
        [self.photoButton.widthAnchor constraintEqualToConstant:34.0],
        [self.photoButton.heightAnchor constraintEqualToConstant:34.0],

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
    [self applyChatAppearance];
    [self loadMessages];
    [self loadSpeakerDetails];
    [self refreshSparks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.uiActive = YES;
    if (self.streamDirty) {
        self.streamDirty = NO;
        NSInteger count = self.messages.count;
        if (count > 0) {
            [self safeReloadRows:[NSSet setWithObject:[NSIndexPath indexPathForRow:count - 1 inSection:0]]];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.uiActive = NO;
    // Do not leave a half-updated table behind when a modal/push cancels
    // streaming-driven reloads; the next appearance catches up.
    [self cancelScheduledStreamFlush];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.stream cancel];
    [self.variantStream cancel];
}

- (void)refreshNavigationTitle {
    NSString *name = self.chatTitle.length ? self.chatTitle : @"";
    if (self.chatNumber > 0) {
        self.title = [NSString stringWithFormat:@"%@ · чат №%lu", name, (unsigned long)self.chatNumber];
    } else {
        self.title = name;
    }
}

- (void)applyChatAppearance {
    LumiChatAppearance *appearance = [LumiChatAppearance sharedAppearance];
    self.view.backgroundColor = appearance.chatBackgroundColor;
    self.tableView.backgroundColor = appearance.chatBackgroundColor;
    self.inputBar.backgroundColor = appearance.inputBarColor;
    self.inputField.tintColor = appearance.boldColor;
    self.inputField.textColor = appearance.characterTextColor;
    self.inputField.backgroundColor = appearance.characterBubbleColor;
    self.sendButton.backgroundColor = appearance.boldColor;
    self.spinner.color = appearance.boldColor;
    self.navigationItem.rightBarButtonItem.tintColor = appearance.boldColor;
    [self safeReloadTable];
}

- (void)infoTapped {
    LumiChatInfoViewController *controller = [[LumiChatInfoViewController alloc] initWithChat:self.chat
                                                                                        item:self.chatItem
                                                                                        kind:self.chatKind];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)presentImageURL:(NSString *)urlString title:(NSString *)title {
    if (!urlString.length) {
        return;
    }
    LumiImageViewerViewController *viewer = [[LumiImageViewerViewController alloc] initWithImageURL:urlString title:title];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)registerCastMembersFrom:(id)container {
    NSDictionary *dictionary = LumiAsDictionary(container);
    if (!dictionary) {
        return;
    }
    if (!self.speakerIndex) {
        self.speakerIndex = [NSMutableDictionary dictionary];
    }
    NSArray *cast = LumiAsArray(dictionary[@"cast_members"]) ?: LumiAsArray(dictionary[@"cast"]);
    for (id member in cast) {
        NSDictionary *entry = LumiAsDictionary(member);
        NSString *name = LumiSpeakerKey(LumiAsString(LumiValue(entry, @"name")));
        if (!name.length) {
            continue;
        }
        NSString *avatar = LumiAsString(LumiValue(entry, @"avatar_url"));
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"name"] = name;
        if (avatar.length) {
            record[@"avatar_url"] = avatar;
        }
        NSString *descriptionText = LumiAsString(LumiValue(entry, @"description"));
        if (descriptionText.length) {
            record[@"description"] = descriptionText;
        }
        NSString *identifier = LumiAsString(LumiValue(entry, @"id"));
        if (identifier.length) {
            record[@"id"] = identifier;
        }
        NSDictionary *existing = self.speakerIndex[name];
        if (!existing || avatar.length) {
            self.speakerIndex[name] = record;
        }
    }
    NSDictionary *target = LumiAsDictionary(LumiValue(dictionary, @"target"));
    NSString *targetName = LumiSpeakerKey(LumiAsString(LumiValue(target, @"name")));
    NSString *targetAvatar = LumiAsString(LumiValue(target, @"avatar_url"));
    if (targetName.length && targetAvatar.length) {
        self.speakerIndex[targetName] = @{@"name": targetName, @"avatar_url": targetAvatar};
    }
}

- (void)buildSpeakerIndexIfNeeded {
    if (self.speakerIndexBuilt) {
        return;
    }
    self.speakerIndexBuilt = YES;
    if (!self.speakerIndex) {
        self.speakerIndex = [NSMutableDictionary dictionary];
    }
    [self registerCastMembersFrom:self.chat];
    [self registerCastMembersFrom:self.chatItem];
    LumiCatalogStore *store = [LumiCatalogStore sharedStore];
    for (NSDictionary *item in store.characters) {
        NSString *name = LumiSpeakerKey(LumiAsString(item[@"name"]));
        if (!name.length || self.speakerIndex[name]) {
            continue;
        }
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"name"] = name;
        NSString *avatar = LumiAsString(item[@"avatar_url"]);
        if (avatar.length) {
            record[@"avatar_url"] = avatar;
        }
        self.speakerIndex[name] = record;
    }
    for (NSDictionary *item in store.stories) {
        [self registerCastMembersFrom:item];
        NSString *title = LumiSpeakerKey(LumiAsString(item[@"title"]));
        if (!title.length || self.speakerIndex[title]) {
            continue;
        }
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"name"] = title;
        NSString *avatar = LumiAsString(item[@"avatar_url"]);
        if (avatar.length) {
            record[@"avatar_url"] = avatar;
        }
        self.speakerIndex[title] = record;
    }
}

- (NSDictionary *)speakerNamed:(NSString *)name {
    NSString *key = LumiSpeakerKey(name);
    if (!key.length) {
        return nil;
    }
    [self buildSpeakerIndexIfNeeded];
    return self.speakerIndex[key];
}

/// Preloads avatars for every character that speaks in the loaded messages, so
/// the inline `**Name**` chips can be drawn inline in the attributed text.
- (void)prepareSpeakerImages {
    [self buildSpeakerIndexIfNeeded];
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSDictionary *message in self.messages) {
        if ([message[@"is_user"] boolValue]) {
            continue;
        }
        for (NSString *name in [LumiRichTextRenderer boldNamesInText:LumiAsString(message[@"content"])]) {
            [names addObject:name];
        }
        NSString *speakerName = LumiSpeakerKey(LumiAsString(message[@"speaker_name"]));
        if (speakerName.length) {
            [names addObject:speakerName];
        }
    }
    __weak typeof(self) weakSelf = self;
    for (NSString *name in names) {
        NSDictionary *speaker = [self speakerNamed:name];
        NSString *avatar = LumiAsString(speaker[@"avatar_url"]);
        if (!avatar.length) {
            continue;
        }
        UIImage *cached = [[LumiImageLoader sharedLoader] cachedImageForURLString:avatar];
        if (cached) {
            self.speakerImages[name] = cached;
            continue;
        }
        [[LumiImageLoader sharedLoader] loadURLString:avatar completion:^(UIImage *image) {
            if (!image) {
                // At launch the image session competes with the catalog crawl,
                // so the first burst of portrait requests can time out. Without
                // a retry the inline portrait stayed blank for the whole chat.
                [self scheduleSpeakerImageRetry];
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                LumiChatViewController *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                strongSelf.speakerImages[name] = image;
                [strongSelf scheduleSpeakerReload];
            });
        }];
    }
}

- (void)scheduleSpeakerImageRetry {
    if (self.speakerImageRetryScheduled || self.speakerImageRetryRounds >= 3) {
        return;
    }
    self.speakerImageRetryScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LumiChatViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.speakerImageRetryScheduled = NO;
        strongSelf.speakerImageRetryRounds += 1;
        [strongSelf prepareSpeakerImages];
    });
}

- (void)scheduleSpeakerReload {
    if (self.speakerReloadScheduled) {
        return;
    }
    self.speakerReloadScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        LumiChatViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.speakerReloadScheduled = NO;
        [strongSelf safeReloadTable];
    });
}

/// Story chats only carry the cast list in the story detail payload, so fetch
/// it once to learn every `**Name**` portrait for the inline chips.
- (void)loadSpeakerDetails {
    NSString *identifier = LumiAsString(self.chatItem[@"id"]);
    if (!identifier.length) {
        NSDictionary *target = LumiAsDictionary(LumiValue(self.chat, @"target"));
        identifier = LumiAsString(LumiValue(target, @"id"));
    }
    if (!identifier.length) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    LumiAPICompletion completion = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSDictionary *detail = LumiAsDictionary(result);
        if (!strongSelf || !detail) {
            return;
        }
        [strongSelf registerCastMembersFrom:detail];
        [strongSelf prepareSpeakerImages];
        [strongSelf safeReloadTable];
    };
    if (self.chatKind == LumiDetailKindStory) {
        [[LumiAPI sharedClient] fetchStoryWithID:identifier completion:completion];
    } else {
        [[LumiAPI sharedClient] fetchCharacterWithID:identifier completion:completion];
    }
}

- (void)catalogUpdated {
    self.speakerIndex = nil;
    self.speakerIndexBuilt = NO;
    [self.speakerImages removeAllObjects];
    [self safeReloadTable];
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
        if (!weakSelf.readMarked) {
            weakSelf.readMarked = YES;
            [[LumiAPI sharedClient] markChatRead:weakSelf.chatID];
        }
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
    // Story payloads carry the cast list; registering it makes `**Имя**`
    // speakers resolve to their own portraits instead of the story cover.
    [self registerCastMembersFrom:chat];
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

    NSString *avatar = LumiAsString(LumiValue(message, @"avatar_url"))
        ?: LumiAsString(LumiValue(message, @"character_avatar_url"))
        ?: LumiAsString(LumiValue(message, @"speaker_avatar_url"));
    NSString *speakerName = LumiAsString(LumiValue(message, @"character_name"))
        ?: LumiAsString(LumiValue(message, @"speaker_name"));
    for (NSString *key in @[@"character", @"speaker", @"persona", @"target"]) {
        NSDictionary *nested = LumiAsDictionary(LumiValue(message, key));
        if (!nested) {
            continue;
        }
        if (!avatar.length) {
            avatar = LumiAsString(LumiValue(nested, @"avatar_url"));
        }
        if (!speakerName.length) {
            speakerName = LumiAsString(LumiValue(nested, @"name"));
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"content"] = content;
    result[@"is_user"] = @(isUser);
    if (avatar.length) {
        result[@"avatar_url"] = avatar;
    }
    if (speakerName.length) {
        result[@"speaker_name"] = speakerName;
    }
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
    NSArray *rawVariants = LumiAsArray(LumiValue(message, @"variants"));
    NSMutableArray<NSString *> *variantContents = [NSMutableArray array];
    for (id item in rawVariants) {
        if ([item isKindOfClass:[NSString class]]) {
            [variantContents addObject:item];
            continue;
        }
        NSDictionary *dictionary = LumiAsDictionary(item);
        NSString *variantContent = LumiStringValue(LumiValue(dictionary, @"content"));
        if (variantContent.length) {
            [variantContents addObject:variantContent];
        }
    }
    NSInteger activeIndex = [LumiAsNumber(LumiValue(message, @"active_variant_index")) integerValue];
    NSInteger variantsCount = [LumiAsNumber(LumiValue(message, @"variants_count")) integerValue];
    if (variantContents.count) {
        result[@"variants"] = variantContents;
        result[@"active_variant_index"] = @(MAX(0, MIN(activeIndex, (NSInteger)variantContents.count - 1)));
        result[@"variants_count"] = @(MAX(variantsCount, (NSInteger)variantContents.count));
        if (!content.length) {
            NSInteger safeIndex = MAX(0, MIN(activeIndex, (NSInteger)variantContents.count - 1));
            result[@"content"] = variantContents[safeIndex];
            photos = LumiPhotoURLsInMessage(@{}, variantContents[safeIndex]);
        }
    } else if (variantsCount > 1) {
        result[@"variants_count"] = @(variantsCount);
        result[@"active_variant_index"] = @(MAX(0, activeIndex));
    }
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
    [self prepareSpeakerImages];
    [self safeReloadTable];
    self.stateLabel.text = self.messages.count ? nil : @"Напишите первое сообщение";
    [self scrollToBottomAnimated:NO];
    if (self.messages.count && !self.readMarked) {
        self.readMarked = YES;
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
    if (self.editingMessageID.length) {
        if (!text.length) {
            [self exitEditMode];
            return;
        }
        [self commitEditWithText:text];
        return;
    }
    if (!text.length || self.sending) {
        return;
    }
    self.inputField.text = @"";
    self.sending = YES;
    self.readMarked = NO;
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
        [self cancelScheduledStreamFlush];
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
                // Rescanning megabytes of Markdown for image tags on every token
                // was burning the main thread. Cheap pre-check first.
                BOOL maybeHasPhoto = [combined rangeOfString:@"[photo]" options:NSCaseInsensitiveSearch].location != NSNotFound
                    || [content rangeOfString:@"http" options:NSCaseInsensitiveSearch].location != NSNotFound
                    || [content rangeOfString:@"]("].location != NSNotFound;
                if (maybeHasPhoto) {
                    NSArray *photos = LumiPhotoURLsInMessage(@{}, combined);
                    if (photos.count) {
                        assistant[@"photo_urls"] = photos;
                    }
                }
                [self scheduleStreamFlush];
            }
        }
        return;
    }
    if ([type isEqualToString:@"intro_message"]) {
        [self cancelScheduledStreamFlush];
        NSDictionary *message = LumiAsDictionary(LumiValue(payload, @"message")) ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (normalized) {
            [self.messages addObject:normalized];
            [self reloadAllRows];
            [self scrollToBottomAnimated:YES];
        }
        return;
    }
    if ([type isEqualToString:@"done"]) {
        [self cancelScheduledStreamFlush];
        NSDictionary *message = LumiAsDictionary(LumiValue(payload, @"message")) ?: payload;
        NSMutableDictionary *normalized = [self normalizedMessage:message];
        if (!normalized) {
            return;
        }
        normalized[@"variants"] = @[LumiAsString(normalized[@"content"]) ?: @""];
        normalized[@"active_variant_index"] = @0;
        normalized[@"variants_count"] = @1;
        NSMutableDictionary *assistant = [self pendingAssistantMessage];
        NSInteger reloadRow = -1;
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
                reloadRow = (NSInteger)index;
            } else {
                [self.messages addObject:normalized];
            }
        } else {
            [self.messages addObject:normalized];
        }
        if (reloadRow == (NSInteger)self.messages.count - 1) {
            // Streaming already painted this bubble; a full reload would make the
            // whole list re-layout and jump.
            [self reloadLastRows];
        } else {
            [self reloadAllRows];
        }
        [self scrollToBottomAnimated:YES];
        return;
    }
    if ([type isEqualToString:@"variant_done"]) {
        [self applyVariantPayload:payload fallbackMessageID:nil];
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
    // While the user reads history (or is on another screen), keep mutating the
    // model but leave the table alone: re-laying out a growing bubble off-screen
    // is pure waste.
    if (!self.uiActive || ![self isNearBottom]) {
        self.streamDirty = YES;
        return;
    }
    self.streamDirty = NO;
    [self safeReloadRows:[NSSet setWithObject:[NSIndexPath indexPathForRow:count - 1 inSection:0]]];
    [self scrollToBottomAnimated:NO];
}

/// Coalesces per-token stream deltas into ~12 UI updates per second.
- (void)scheduleStreamFlush {
    if (self.streamFlushScheduled) {
        return;
    }
    self.streamFlushScheduled = YES;
    NSUInteger token = self.streamFlushToken;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LumiChatViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (token != strongSelf.streamFlushToken) {
            return;
        }
        strongSelf.streamFlushScheduled = NO;
        [strongSelf reloadLastRows];
    });
}

- (void)cancelScheduledStreamFlush {
    self.streamFlushToken += 1;
    self.streamFlushScheduled = NO;
}

- (BOOL)isNearBottom {
    UIScrollView *scrollView = self.tableView;
    if (scrollView.bounds.size.height <= 0.0) {
        return YES;
    }
    CGFloat visibleBottom = scrollView.contentOffset.y + scrollView.bounds.size.height - scrollView.contentInset.bottom;
    return visibleBottom >= scrollView.contentSize.height - 160.0;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.streamDirty && scrollView == self.tableView && [self isNearBottom]) {
        self.streamDirty = NO;
        NSInteger count = self.messages.count;
        if (count > 0) {
            [self safeReloadRows:[NSSet setWithObject:[NSIndexPath indexPathForRow:count - 1 inSection:0]]];
        }
    }
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
    [self cancelScheduledStreamFlush];
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

#pragma mark - Sparks & photos

static const NSInteger kLumiPhotoSparkCost = 10;

- (void)refreshSparks {
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] fetchSparksWithCompletion:^(id result, NSError *error) {
        if (error) {
            [LumiDiagnostics log:@"искры: не загрузились — %@", error.localizedDescription];
            return;
        }
        NSDictionary *dictionary = LumiAsDictionary(result);
        NSNumber *balance = LumiAsNumber(LumiValue(dictionary, @"balance"))
            ?: LumiAsNumber(LumiValue(dictionary, @"sparks_balance"))
            ?: LumiAsNumber(LumiValue(dictionary, @"sparks"));
        if (!balance) {
            return;
        }
        weakSelf.sparksBalance = balance.integerValue;
        weakSelf.sparksKnown = YES;
        [weakSelf updateSparksButton];
    }];
}

- (void)updateSparksButton {
    NSString *title = self.sparksKnown
        ? [NSString stringWithFormat:@"⚡ %ld", (long)self.sparksBalance]
        : @"⚡ —";
    [self.sparksButton setTitle:title forState:UIControlStateNormal];
}

- (void)sparksTapped {
    [self refreshSparks];
    NSString *message = nil;
    if (!self.sparksKnown) {
        message = @"Загружаю баланс искр…";
    } else if (self.sparksBalance < kLumiPhotoSparkCost) {
        message = [NSString stringWithFormat:@"Баланс: %ld искр.\n\nОдно фото стоит %ld искр — пока недостаточно. Бесплатных генераций не осталось.",
                   (long)self.sparksBalance, (long)kLumiPhotoSparkCost];
    } else {
        NSInteger photos = self.sparksBalance / kLumiPhotoSparkCost;
        message = [NSString stringWithFormat:@"Баланс: %ld искр.\n\nОдно фото стоит %ld искр — можно создать ещё %ld фото.",
                   (long)self.sparksBalance, (long)kLumiPhotoSparkCost, (long)photos];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Искры"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)photoTapped {
    if (self.photoGenerating) {
        return;
    }
    [self refreshSparks];
    if (self.sparksKnown && self.sparksBalance < kLumiPhotoSparkCost) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Недостаточно искр"
                             message:[NSString stringWithFormat:@"Для фото нужно %ld искр, на балансе %ld.",
                                      (long)kLumiPhotoSparkCost, (long)self.sparksBalance]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Сгенерировать фото"
                                                                   message:[NSString stringWithFormat:@"%ld искр за фото", (long)kLumiPhotoSparkCost]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Быстрая · 20–30 сек" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self generatePhotoWithQuality:@"standard"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Детальная · 40–60 сек" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self generatePhotoWithQuality:@"enhanced"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.photoButton;
    sheet.popoverPresentationController.sourceRect = self.photoButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)generatePhotoWithQuality:(NSString *)quality {
    if (self.photoGenerating || self.sending || !self.chatID.length) {
        return;
    }
    self.photoGenerating = YES;
    NSMutableDictionary *placeholder = [NSMutableDictionary dictionary];
    placeholder[@"content"] = @"";
    placeholder[@"is_user"] = @NO;
    placeholder[@"pending"] = @YES;
    placeholder[@"generating_photo"] = @YES;
    [self.messages addObject:placeholder];
    [self reloadAllRows];
    [self scrollToBottomAnimated:YES];

    [LumiDiagnostics log:@"чат %@: генерация фото (%@)", self.chatID, quality];
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] generateChatPhotoForChatID:self.chatID
                                               quality:quality
                                            completion:^(id result, NSError *error) {
        weakSelf.photoGenerating = NO;
        if (error) {
            NSUInteger index = [weakSelf.messages indexOfObjectIdenticalTo:placeholder];
            if (index != NSNotFound) {
                [weakSelf.messages removeObjectAtIndex:index];
            }
            [weakSelf reloadAllRows];
            [LumiDiagnostics log:@"чат %@: фото не создалось — %@", weakSelf.chatID, error.localizedDescription];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось создать фото"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            [weakSelf refreshSparks];
            return;
        }
        NSMutableDictionary *normalized = [weakSelf normalizedMessage:LumiAsDictionary(result)];
        if (!normalized) {
            normalized = [NSMutableDictionary dictionary];
            normalized[@"content"] = @"";
            normalized[@"is_user"] = @NO;
        }
        normalized[@"pending"] = @NO;
        NSUInteger index = [weakSelf.messages indexOfObjectIdenticalTo:placeholder];
        if (index != NSNotFound) {
            [weakSelf.messages replaceObjectAtIndex:index withObject:normalized];
        } else {
            [weakSelf.messages addObject:normalized];
        }
        [weakSelf reloadAllRows];
        [weakSelf scrollToBottomAnimated:YES];
        [weakSelf refreshSparks];
    }];
}

#pragma mark - Editing & variants

- (NSUInteger)indexOfMessageWithID:(NSString *)messageID {
    if (!messageID.length) {
        return NSNotFound;
    }
    for (NSUInteger index = 0; index < self.messages.count; index++) {
        if ([LumiStringValue(self.messages[index][@"id"]) isEqualToString:messageID]) {
            return index;
        }
    }
    return NSNotFound;
}

- (void)presentMessageMenuForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.messages.count) {
        return;
    }
    NSDictionary *message = self.messages[row];
    NSString *messageID = LumiStringValue(message[@"id"]);
    BOOL isUser = [message[@"is_user"] boolValue];
    BOOL pending = [message[@"pending"] boolValue];
    NSString *content = LumiStringValue(message[@"content"]) ?: @"";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    if (messageID.length && !pending) {
        [sheet addAction:[UIAlertAction actionWithTitle:(isUser ? @"Редактировать сообщение" : @"Редактировать ответ")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [weakSelf beginEditingMessageWithID:messageID];
        }]];
    }
    if (!isUser && messageID.length && !pending && !self.regenerating) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Перегенерировать"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [weakSelf regenerateMessageWithID:messageID];
        }]];
    }

    // Удалить сообщение
    if (messageID.length && !pending) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Удалить сообщение"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
            [weakSelf deleteMessageWithID:messageID atRow:row];
        }]];
    }

    // Новый чат от этого сообщения (fork)
    if (messageID.length && !pending) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Новый чат от этого сообщения"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
            [weakSelf forkChatFromMessageID:messageID];
        }]];
    }

    // Продолжить диалог (персонаж отвечает без сообщения пользователя)
    if (!isUser && !pending && !self.sending && !self.loading) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Продолжить диалог"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
            [weakSelf continueDialog];
        }]];
    }

    // Новый чат с тем же персонажем
    if (!self.sending && !self.loading) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Новый чат с этим персонажем"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
            [weakSelf startNewChatWithSameCharacter];
        }]];
    }

    if (content.length) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Копировать"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [UIPasteboard generalPasteboard].string = content;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                CGRectGetMaxY(self.view.bounds) - 80.0,
                                                                1.0, 1.0);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)beginEditingMessageWithID:(NSString *)messageID {
    NSUInteger index = [self indexOfMessageWithID:messageID];
    if (index == NSNotFound) {
        return;
    }
    NSMutableDictionary *message = self.messages[index];
    NSString *content = LumiStringValue(message[@"content"]) ?: @"";
    self.editingMessageID = messageID;
    self.editingOriginalContent = content;
    self.inputField.text = content;
    self.inputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Редактирование…"
                                                                           attributes:@{NSForegroundColorAttributeName: LumiMutedColor()}];
    [self.sendButton setTitle:@"✓" forState:UIControlStateNormal];
    [self.inputField becomeFirstResponder];
}

- (void)exitEditMode {
    self.editingMessageID = nil;
    self.editingOriginalContent = nil;
    self.inputField.text = @"";
    self.inputField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Сообщение…"
                                                                           attributes:@{NSForegroundColorAttributeName: LumiMutedColor()}];
    [self.sendButton setTitle:@"→" forState:UIControlStateNormal];
}

- (void)commitEditWithText:(NSString *)text {
    NSString *messageID = self.editingMessageID;
    NSUInteger index = [self indexOfMessageWithID:messageID];
    if (index == NSNotFound) {
        [self exitEditMode];
        return;
    }
    NSMutableDictionary *message = self.messages[index];
    NSString *original = LumiStringValue(message[@"content"]) ?: @"";
    [self exitEditMode];
    if ([original isEqualToString:text] || self.sending) {
        return;
    }

    [self applyEditedContent:text toMessage:message];
    [self reloadAllRows];
    self.sending = YES;
    self.sendButton.enabled = NO;
    self.sendButton.alpha = 0.5;

    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] editMessageWithID:messageID
                                       chatID:self.chatID
                                      content:text
                                   completion:^(id result, NSError *error) {
        weakSelf.sending = NO;
        weakSelf.sendButton.enabled = YES;
        weakSelf.sendButton.alpha = 1.0;
        if (error) {
            [weakSelf applyEditedContent:original toMessage:message];
            [weakSelf reloadAllRows];
            [LumiDiagnostics log:@"чат %@: правка не сохранилась — %@", weakSelf.chatID, error.localizedDescription];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось сохранить"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        NSMutableDictionary *normalized = [weakSelf normalizedMessage:LumiAsDictionary(result)];
        if (normalized) {
            if (!LumiStringValue(normalized[@"id"]).length) {
                normalized[@"id"] = messageID;
            }
            normalized[@"is_user"] = message[@"is_user"];
            normalized[@"pending"] = @NO;
            NSUInteger currentIndex = [weakSelf indexOfMessageWithID:messageID];
            if (currentIndex != NSNotFound) {
                [weakSelf.messages replaceObjectAtIndex:currentIndex withObject:normalized];
                [weakSelf reloadAllRows];
            }
        }
    }];
}

- (void)applyEditedContent:(NSString *)text toMessage:(NSMutableDictionary *)message {
    if (!message) {
        return;
    }
    message[@"content"] = text ?: @"";
    NSArray *existingVariants = LumiAsArray(message[@"variants"]);
    if (existingVariants.count) {
        NSMutableArray *variants = [existingVariants mutableCopy];
        NSInteger active = [LumiAsNumber(message[@"active_variant_index"]) integerValue];
        active = MAX(0, MIN(active, (NSInteger)variants.count - 1));
        variants[active] = text ?: @"";
        message[@"variants"] = variants;
        message[@"active_variant_index"] = @(active);
    }
    NSArray *photos = LumiPhotoURLsInMessage(@{}, text ?: @"");
    message[@"photo_urls"] = photos.count ? photos : nil;
    message[@"pending"] = @NO;
}

- (void)regenerateMessageWithID:(NSString *)messageID {
    if (self.regenerating || self.sending || !messageID.length || !self.chatID.length) {
        return;
    }
    self.regenerating = YES;
    self.stateLabel.text = @"Генерирую новый вариант…";
    [self.spinner startAnimating];

    [LumiDiagnostics log:@"чат %@: перегенерация %@", self.chatID, messageID];
    __weak typeof(self) weakSelf = self;
    self.variantStream = [[LumiAPI sharedClient] regenerateMessageWithID:messageID
                                                                 chatID:self.chatID
                                                           eventHandler:^(NSString *type, NSDictionary *payload) {
        if ([type isEqualToString:@"variant_done"]) {
            [weakSelf applyVariantPayload:payload fallbackMessageID:messageID];
        } else if ([type isEqualToString:@"error"]) {
            NSString *message = LumiStringValue(LumiValue(payload, @"error"))
                ?: LumiStringValue(LumiValue(payload, @"message"))
                ?: @"Не удалось перегенерировать";
            [LumiDiagnostics log:@"чат %@: перегенерация отклонена — %@", weakSelf.chatID, message];
        }
    } completion:^(NSError *error) {
        weakSelf.regenerating = NO;
        weakSelf.variantStream = nil;
        [weakSelf.spinner stopAnimating];
        if (weakSelf.messages.count) {
            weakSelf.stateLabel.text = nil;
        }
        if (error) {
            [LumiDiagnostics log:@"чат %@: перегенерация не удалась — %@", weakSelf.chatID, error.localizedDescription];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось перегенерировать"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)applyVariantPayload:(NSDictionary *)payload fallbackMessageID:(NSString *)fallbackID {
    NSString *messageID = LumiStringValue(LumiValue(payload, @"message_id")) ?: fallbackID;
    NSUInteger index = [self indexOfMessageWithID:messageID];
    if (index == NSNotFound) {
        return;
    }
    NSString *content = LumiStringValue(LumiValue(payload, @"content")) ?: @"";
    if (!content.length) {
        return;
    }
    NSInteger variantIndex = [LumiAsNumber(LumiValue(payload, @"variant_index")) integerValue];
    NSInteger variantsCount = [LumiAsNumber(LumiValue(payload, @"variants_count")) integerValue];
    variantIndex = MAX(0, variantIndex);

    NSMutableDictionary *message = self.messages[index];
    NSMutableArray *variants = [LumiAsArray(message[@"variants"]) mutableCopy];
    if (!variants) {
        variants = [NSMutableArray array];
        NSString *existing = LumiStringValue(message[@"content"]);
        if (existing.length) {
            [variants addObject:existing];
        }
    }
    while ((NSInteger)variants.count <= variantIndex) {
        [variants addObject:content];
    }
    variants[variantIndex] = content;
    message[@"variants"] = variants;
    message[@"content"] = content;
    message[@"active_variant_index"] = @(variantIndex);
    message[@"variants_count"] = @(MAX(variantsCount, (NSInteger)variants.count));
    NSArray *photos = LumiPhotoURLsInMessage(@{}, content);
    message[@"photo_urls"] = photos.count ? photos : nil;
    message[@"pending"] = @NO;
    [self reloadAllRows];
    [self scrollToBottomAnimated:YES];
}

- (void)stepVariantForRow:(NSInteger)row delta:(NSInteger)delta {
    if (row < 0 || row >= (NSInteger)self.messages.count) {
        return;
    }
    NSMutableDictionary *message = self.messages[row];
    NSArray *variants = LumiAsArray(message[@"variants"]);
    if (variants.count < 2) {
        return;
    }
    NSString *messageID = LumiStringValue(message[@"id"]);
    if (!messageID.length) {
        return;
    }
    NSInteger current = [LumiAsNumber(message[@"active_variant_index"]) integerValue];
    NSInteger next = MAX(0, MIN(current + delta, (NSInteger)variants.count - 1));
    if (next == current) {
        return;
    }
    message[@"active_variant_index"] = @(next);
    message[@"content"] = variants[next];
    NSArray *photos = LumiPhotoURLsInMessage(@{}, variants[next]);
    message[@"photo_urls"] = photos.count ? photos : nil;
    [self reloadAllRows];

    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] setActiveVariantIndex:next
                                     forMessageID:messageID
                                           chatID:self.chatID
                                       completion:^(id result, NSError *error) {
        if (!error) {
            return;
        }
        [LumiDiagnostics log:@"чат %@: вариант не переключился — %@", weakSelf.chatID, error.localizedDescription];
        NSUInteger index = [weakSelf indexOfMessageWithID:messageID];
        if (index == NSNotFound) {
            return;
        }
        NSMutableDictionary *currentMessage = weakSelf.messages[index];
        currentMessage[@"active_variant_index"] = @(current);
        currentMessage[@"content"] = variants[current];
        NSArray *currentPhotos = LumiPhotoURLsInMessage(@{}, variants[current]);
        currentMessage[@"photo_urls"] = currentPhotos.count ? currentPhotos : nil;
        [weakSelf reloadAllRows];
    }];
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
        [cell configureWithText:@""
                         isUser:NO
                        pending:NO
                      photoURLs:@[]
                  variantsCount:1
                    activeIndex:0
                      avatarURL:@""
                  speakerImages:self.speakerImages];
        return cell;
    }
    NSDictionary *message = self.messages[indexPath.row];
    BOOL isUser = [message[@"is_user"] boolValue];
    BOOL pending = [message[@"pending"] boolValue];
    NSArray *variants = LumiAsArray(message[@"variants"]);
    NSInteger variantsCount = MAX(1, [LumiAsNumber(message[@"variants_count"]) integerValue]);
    if (variants.count > 0) {
        variantsCount = MAX(variantsCount, (NSInteger)variants.count);
    }
    NSInteger activeIndex = [LumiAsNumber(message[@"active_variant_index"]) integerValue];
    NSString *avatarURL = nil;
    NSString *speakerName = nil;
    if (!isUser) {
        avatarURL = LumiStringValue(message[@"avatar_url"]);
        speakerName = LumiStringValue(message[@"speaker_name"]);
        if (!avatarURL.length) {
            NSString *leadingName = LumiLeadingBoldName(LumiStringValue(message[@"content"]));
            NSDictionary *speaker = [self speakerNamed:leadingName];
            if (speaker) {
                avatarURL = LumiStringValue(speaker[@"avatar_url"]);
                if (!speakerName.length) {
                    speakerName = LumiAsString(speaker[@"name"]) ?: LumiAsString(speaker[@"title"]);
                }
            }
        }
        if (!avatarURL.length) {
            avatarURL = self.avatarURL;
            if (!speakerName.length) {
                speakerName = self.chatTitle;
            }
        }
    }
    [cell configureWithText:LumiStringValue(message[@"content"])
                     isUser:isUser
                    pending:pending
                  photoURLs:LumiAsArray(message[@"photo_urls"]) ?: @[]
              variantsCount:variantsCount
                activeIndex:activeIndex
                  avatarURL:avatarURL ?: @""
              speakerImages:self.speakerImages];
    __weak typeof(self) weakSelf = self;
    NSInteger row = indexPath.row;
    cell.longPressHandler = ^{
        [weakSelf presentMessageMenuForRow:row];
    };
    if (avatarURL.length) {
        NSString *speaker = speakerName ?: self.chatTitle;
        cell.avatarTapHandler = ^{
            [weakSelf presentImageURL:avatarURL title:speaker];
        };
    }
    cell.variantStepHandler = ^(NSInteger delta) {
        [weakSelf stepVariantForRow:row delta:delta];
    };
    return cell;
}

#pragma mark - New Chat Actions

- (void)deleteMessageWithID:(NSString *)messageID atRow:(NSInteger)row {
    if (!messageID.length || !self.chatID.length) {
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Удалить сообщение"
                                                                   message:@"Это действие нельзя отменить. Сообщение будет удалено навсегда."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Удалить" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf performDeleteMessage:messageID atRow:row];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performDeleteMessage:(NSString *)messageID atRow:(NSInteger)row {
    self.sending = YES;
    self.sendButton.enabled = NO;
    self.sendButton.alpha = 0.5;
    
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] deleteMessageWithID:messageID chatID:self.chatID completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.sending = NO;
        strongSelf.sendButton.enabled = YES;
        strongSelf.sendButton.alpha = 1.0;
        
        if (error) {
            [LumiDiagnostics log:@"чат %@: удаление сообщения не удалось — %@", strongSelf.chatID, error.localizedDescription];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось удалить"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        // Удаляем сообщение локально
        if (row >= 0 && row < (NSInteger)strongSelf.messages.count) {
            [strongSelf.messages removeObjectAtIndex:row];
            [strongSelf.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                          withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        [LumiDiagnostics log:@"чат %@: сообщение %@ удалено", strongSelf.chatID, messageID];
    }];
}

- (void)forkChatFromMessageID:(NSString *)messageID {
    if (!messageID.length || !self.chatID.length) {
        return;
    }
    
    // Находим сообщение и получаем его контент для контекста
    NSDictionary *message = nil;
    for (NSDictionary *msg in self.messages) {
        if ([LumiStringValue(msg[@"id"]) isEqualToString:messageID]) {
            message = msg;
            break;
        }
    }
    if (!message) return;
    
    NSString *content = LumiStringValue(message[@"content"]);
    NSString *targetID = self.chat[@"target_id"] ?: self.chat[@"character_id"] ?: self.chat[@"story_id"];
    NSString *kind = self.chat[@"target_kind"] ?: self.chat[@"kind"];
    LumiDetailKind detailKind = ([kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"])
        ? LumiDetailKindStory : LumiDetailKindCharacter;
    NSDictionary *item = @{@"id": targetID,
                           @"name": self.chatTitle,
                           @"avatar_url": self.avatarURL};
    
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] forkChatFromMessageID:messageID chatID:self.chatID completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось создать чат"
                                                                           message:error.localizedDescription ?: @"Сервер не вернул данные чата"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        NSDictionary *chat = result[@"chat"] ?: result;
        LumiChatViewController *controller = [[LumiChatViewController alloc] initWithChat:chat item:item kind:detailKind];
        [strongSelf.navigationController pushViewController:controller animated:YES];
    }];
}

- (void)continueDialog {
    if (self.sending || self.loading || !self.chatID.length) {
        return;
    }
    
    // Отправляем пустое сообщение для триггера ответа персонажа
    self.sending = YES;
    self.sendButton.enabled = NO;
    self.sendButton.alpha = 0.5;
    self.inputField.enabled = NO;
    
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] sendMessageToChatID:self.chatID
                                         content:@""
                                        isContinue:YES
                                     completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.sending = NO;
        strongSelf.sendButton.enabled = YES;
        strongSelf.sendButton.alpha = 1.0;
        strongSelf.inputField.enabled = YES;
        
        if (error) {
            [LumiDiagnostics log:@"чат %@: продолжение диалога не удалось — %@", strongSelf.chatID, error.localizedDescription];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось продолжить"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ок" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        // Перезагружаем сообщения
        [strongSelf loadMessages];
        [LumiDiagnostics log:@"чат %@: диалог продолжен", strongSelf.chatID];
    }];
}

- (void)startNewChatWithSameCharacter {
    if (!self.chatID.length) {
        return;
    }
    
    NSString *targetID = self.chat[@"target_id"] ?: self.chat[@"character_id"] ?: self.chat[@"story_id"];
    NSString *kind = self.chat[@"target_kind"] ?: self.chat[@"kind"];
    if (!targetID.length || !kind.length) {
        return;
    }
    
    NSDictionary *item = @{@"id": targetID,
                           @"name": self.chatTitle,
                           @"avatar_url": self.avatarURL};
    
    LumiDetailKind detailKind = ([kind isEqualToString:@"story"] || [kind isEqualToString:@"stories"])
        ? LumiDetailKindStory : LumiDetailKindCharacter;
    
    // Показываем индикатор загрузки
    self.sending = YES;
    self.sendButton.enabled = NO;
    self.sendButton.alpha = 0.5;
    self.inputField.enabled = NO;
    [self.spinner startAnimating];
    self.stateLabel.text = @"Создаю новый чат...";
    
    __weak typeof(self) weakSelf = self;
    LumiAPICompletion completion = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.sending = NO;
        strongSelf.sendButton.enabled = YES;
        strongSelf.sendButton.alpha = 1.0;
        strongSelf.inputField.enabled = YES;
        [strongSelf.spinner stopAnimating];
        strongSelf.stateLabel.text = nil;
        
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

@end
