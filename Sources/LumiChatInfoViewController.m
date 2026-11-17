#import "LumiChatInfoViewController.h"
#import "LumiAPI.h"
#import "LumiChatAppearance.h"
#import "LumiChatAppearanceViewController.h"
#import "LumiDiagnostics.h"
#import "LumiImageLoader.h"
#import "LumiImageViewerViewController.h"
#import "LumiSafe.h"
#import "LumiTheme.h"

static NSArray<NSString *> *LumiAboutKeys(void) {
    return @[@"description", @"backstory", @"personality", @"scenario", @"appearance", @"greeting"];
}

static NSArray<NSString *> *LumiRelationshipNeedles(void) {
    return @[@"relationship", @"relation", @"affection", @"affinity", @"trust", @"bond",
             @"attitude", @"feeling", @"romance", @"dating", @"standing", @"reputation"];
}

static NSArray<NSString *> *LumiMemoryNeedles(void) {
    return @[@"memory", @"memories", @"user_notes", @"chat_summary", @"user_summary",
             @"character_summary", @"notes", @"remember"];
}

static NSString *LumiHumanizedKey(NSString *key) {
    static NSDictionary *labels;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        labels = @{
            @"relationship": @"Отношения",
            @"relationship_description": @"Отношения",
            @"relationship_state": @"Состояние отношений",
            @"relationship_status": @"Статус отношений",
            @"relationship_level": @"Уровень отношений",
            @"relationship_level_name": @"Уровень отношений",
            @"user_relationship": @"Ваши отношения",
            @"affection": @"Привязанность",
            @"affection_level": @"Привязанность",
            @"affinity": @"Симпатия",
            @"trust": @"Доверие",
            @"trust_level": @"Доверие",
            @"bond": @"Связь",
            @"attitude": @"Отношение",
            @"feeling": @"Чувства",
            @"romance": @"Романтика",
            @"dating": @"Встречания",
            @"standing": @"Репутация",
            @"reputation": @"Репутация",
            @"memory": @"Память",
            @"memories": @"Память",
            @"user_notes": @"Заметки",
            @"notes": @"Заметки",
            @"chat_summary": @"О переписке",
            @"user_summary": @"О вас",
            @"character_summary": @"О персонаже",
            @"status": @"Статус",
            @"level": @"Уровень",
            @"value": @"Значение",
            @"score": @"Значение",
            @"name": @"Имя",
            @"title": @"Заголовок",
            @"description": @"Описание",
            @"avatar_url": @"Аватар",
            @"character_id": @"Персонаж",
            @"character": @"Персонаж",
        };
    });
    NSString *label = labels[key];
    if (label.length) {
        return label;
    }
    return [key stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

/// Turns any JSON value into readable text. Dictionaries are flattened into
/// "Label: value" lines, arrays into bullets.
static NSString *LumiReadableValue(id value, NSUInteger depth) {
    if (!value || value == [NSNull null] || depth > 4) {
        return nil;
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return string.length ? string : nil;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            NSString *text = LumiReadableValue(item, depth + 1);
            if (text.length) {
                [parts addObject:text];
            }
        }
        return parts.count ? [parts componentsJoinedByString:@"\n• "] : nil;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in [(NSDictionary *)value allKeys]) {
            NSString *text = LumiReadableValue(((NSDictionary *)value)[key], depth + 1);
            if (text.length) {
                [parts addObject:[NSString stringWithFormat:@"%@: %@", LumiHumanizedKey(key), text]];
            }
        }
        return parts.count ? [parts componentsJoinedByString:@"\n"] : nil;
    }
    return nil;
}

static BOOL LumiKeyMatchesAny(NSString *key, NSArray<NSString *> *needles) {
    NSString *lowercase = key.lowercaseString;
    for (NSString *needle in needles) {
        if ([lowercase containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static NSString *LumiEntryNameFromDictionary(NSDictionary *dictionary, NSString *fallback) {
    NSString *name = LumiAsString(LumiValue(dictionary, @"character_name"))
        ?: LumiAsString(LumiValue(dictionary, @"name"))
        ?: LumiAsString(LumiValue(dictionary, @"display_name"))
        ?: LumiAsString(LumiValue(dictionary, @"title"));
    if (name.length) {
        return name;
    }
    id character = LumiValue(dictionary, @"character");
    if ([character isKindOfClass:[NSDictionary class]]) {
        name = LumiAsString(LumiValue(character, @"name"))
            ?: LumiAsString(LumiValue(character, @"title"));
    } else if ([character isKindOfClass:[NSString class]]) {
        name = character;
    }
    return name.length ? name : fallback;
}

static NSString *LumiEntryAvatarFromDictionary(NSDictionary *dictionary, NSString *fallback) {
    NSString *avatar = LumiAsString(LumiValue(dictionary, @"avatar_url"))
        ?: LumiAsString(LumiValue(dictionary, @"character_avatar_url"));
    if (avatar.length) {
        return avatar;
    }
    NSDictionary *character = LumiAsDictionary(LumiValue(dictionary, @"character"));
    avatar = LumiAsString(LumiValue(character, @"avatar_url"));
    return avatar.length ? avatar : fallback;
}

/// Condenses a cast biography into one readable line: drops a leading
/// "Имя — " that duplicates the row title, collapses newlines and cuts at a
/// word boundary.
static NSString *LumiCondensedText(NSString *text, NSString *name, NSUInteger limit) {
    if (!text.length) {
        return nil;
    }
    NSString *result = text;
    if (name.length) {
        for (NSString *separator in @[@" — ", @" - ", @" – ", @": "]) {
            NSString *prefix = [name stringByAppendingString:separator];
            if ([result hasPrefix:prefix]) {
                result = [result substringFromIndex:prefix.length];
                break;
            }
        }
    }
    result = [result stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (result.length <= limit) {
        return result.length ? result : nil;
    }
    NSString *cut = [result substringToIndex:limit];
    NSRange space = [cut rangeOfString:@" " options:NSBackwardsSearch];
    if (space.location != NSNotFound && space.location > limit / 2) {
        cut = [cut substringToIndex:space.location];
    }
    cut = [cut stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [cut stringByAppendingString:@"…"];
}

/// Walks the whole payload and collects scalar values found under keys that look
/// like relationship or memory state. The API nests these differently between
/// characters and stories, so key sniffing is more robust than a fixed path.
static void LumiCollectState(id value,
                             NSString *contextName,
                             NSString *contextAvatar,
                             BOOL memoryMode,
                             NSMutableArray<NSDictionary *> *output,
                             NSUInteger depth) {
    if (!value || value == [NSNull null] || depth > 5) {
        return;
    }
    NSArray<NSString *> *needles = memoryMode ? LumiMemoryNeedles() : LumiRelationshipNeedles();
    if ([value isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)value) {
            LumiCollectState(item, contextName, contextAvatar, memoryMode, output, depth + 1);
        }
        return;
    }
    if (![value isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *dictionary = (NSDictionary *)value;
    NSString *name = LumiEntryNameFromDictionary(dictionary, contextName);
    NSString *avatar = LumiEntryAvatarFromDictionary(dictionary, contextAvatar);
    for (NSString *key in dictionary) {
        id child = dictionary[key];
        BOOL isContainer = [child isKindOfClass:[NSDictionary class]] || [child isKindOfClass:[NSArray class]];
        BOOL matches = LumiKeyMatchesAny(key, needles);
        if (matches && !isContainer) {
            NSString *text = LumiReadableValue(child, 0);
            if (text.length) {
                [output addObject:@{
                    @"name": name ?: @"",
                    @"avatar_url": avatar ?: @"",
                    @"label": LumiHumanizedKey(key),
                    @"text": text,
                }];
            }
            continue;
        }
        if (isContainer) {
            LumiCollectState(child, name, avatar, memoryMode, output, depth + 1);
        }
    }
}

@interface LumiChatInfoViewController ()
@property (nonatomic, strong) NSMutableDictionary *resolved;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *castMembers;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *relationshipEntries;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *memoryEntries;
@property (nonatomic, assign) LumiDetailKind kind;
@property (nonatomic, copy, nullable) NSString *targetIdentifier;
@property (nonatomic, copy, nullable) NSString *chatID;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *relationshipTitleLabel;
@property (nonatomic, strong) UIStackView *relationshipStack;
@property (nonatomic, strong) UILabel *relationshipLabel;
@property (nonatomic, strong) UILabel *memoryTitleLabel;
@property (nonatomic, strong) UILabel *memoryLabel;
@property (nonatomic, strong) UILabel *aboutTitleLabel;
@property (nonatomic, strong) UILabel *aboutLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)render;
- (void)loadDetail;
- (void)loadChat;
- (UILabel *)labelWithText:(NSString *)text color:(UIColor *)color font:(UIFont *)font;
- (UILabel *)sectionTitleWithText:(NSString *)text;
- (UILabel *)bodyLabel;
- (void)rebuildRelationships;
@end

@implementation LumiChatInfoViewController

- (instancetype)initWithChat:(NSDictionary *)chat
                        item:(NSDictionary *)item
                        kind:(LumiDetailKind)kind {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _kind = kind;
        _resolved = [NSMutableDictionary dictionary];
        _castMembers = [NSMutableArray array];
        _relationshipEntries = [NSMutableArray array];
        _memoryEntries = [NSMutableArray array];
        NSDictionary *chatDictionary = LumiAsDictionary(chat) ?: @{};
        NSDictionary *itemDictionary = LumiAsDictionary(item) ?: @{};
        NSDictionary *target = LumiAsDictionary(LumiValue(chatDictionary, @"target")) ?: @{};
        for (NSDictionary *source in @[target, chatDictionary, itemDictionary]) {
            for (NSString *key in source) {
                id value = source[key];
                if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
                    [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                    _resolved[key] = value;
                }
            }
        }
        NSString *targetID = LumiAsString(LumiValue(chatDictionary, @"target_id"))
            ?: LumiAsString(LumiValue(chatDictionary, @"character_id"))
            ?: LumiAsString(LumiValue(chatDictionary, @"story_id"))
            ?: LumiAsString(LumiValue(target, @"id"))
            ?: LumiAsString(itemDictionary[@"id"]);
        _targetIdentifier = [targetID copy];
        NSString *chatID = LumiAsString(LumiValue(chatDictionary, @"id"))
            ?: LumiAsString(LumiValue(chatDictionary, @"chat_id"))
            ?: LumiAsString(LumiValue(chatDictionary, @"session_id"));
        _chatID = [chatID copy];
        NSString *targetName = LumiAsString(LumiValue(target, @"name"))
            ?: LumiAsString(itemDictionary[@"name"]);
        if (targetName.length && !LumiAsString(_resolved[@"name"]).length) {
            _resolved[@"name"] = targetName;
        }
        NSString *targetAvatar = LumiAsString(LumiValue(target, @"avatar_url"))
            ?: LumiAsString(itemDictionary[@"avatar_url"]);
        if (targetAvatar.length && !LumiAsString(_resolved[@"avatar_url"]).length) {
            _resolved[@"avatar_url"] = targetAvatar;
        }
        [self collectCastFrom:target];
        [self collectCastFrom:chatDictionary];
        [self collectCastFrom:itemDictionary];
    }
    return self;
}

- (void)collectCastFrom:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSArray *cast = LumiAsArray(dictionary[@"cast_members"]) ?: LumiAsArray(dictionary[@"cast"]);
    for (id member in cast) {
        NSDictionary *entry = LumiAsDictionary(member);
        NSString *name = LumiAsString(LumiValue(entry, @"name"));
        if (!name.length) {
            continue;
        }
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"name"] = name;
        NSString *avatar = LumiAsString(LumiValue(entry, @"avatar_url"));
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
        BOOL exists = NO;
        for (NSDictionary *existing in self.castMembers) {
            if ([LumiAsString(existing[@"name"]) isEqualToString:name]) {
                exists = YES;
                break;
            }
        }
        if (!exists) {
            [self.castMembers addObject:record];
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"О чате";
    self.view.backgroundColor = LumiBackgroundColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.stack = [[UIStackView alloc] init];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 10.0;
    [self.scrollView addSubview:self.stack];

    self.avatarButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.avatarButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarButton.layer.cornerRadius = 54.0;
    self.avatarButton.clipsToBounds = YES;
    self.avatarButton.backgroundColor = LumiSurfaceColor();
    [self.avatarButton addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.avatarButton.widthAnchor constraintEqualToConstant:108.0].active = YES;
    [self.avatarButton.heightAnchor constraintEqualToConstant:108.0].active = YES;

    // Remote images must not be assigned to UIButton.imageView: UIKit resets it
    // on layout, which is why the portrait stayed a placeholder before.
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

    UIView *avatarContainer = [[UIView alloc] init];
    [avatarContainer addSubview:self.avatarButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.avatarButton.topAnchor constraintEqualToAnchor:avatarContainer.topAnchor],
        [self.avatarButton.bottomAnchor constraintEqualToAnchor:avatarContainer.bottomAnchor],
        [self.avatarButton.centerXAnchor constraintEqualToAnchor:avatarContainer.centerXAnchor],
    ]];
    [self.stack addArrangedSubview:avatarContainer];
    [self.stack setCustomSpacing:2.0 afterView:avatarContainer];

    UILabel *avatarHint = [self labelWithText:@"Нажмите на аватар, чтобы увеличить"
                                        color:LumiMutedColor()
                                         font:LumiFont(11.0, UIFontWeightRegular)];
    avatarHint.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:avatarHint];
    [self.stack setCustomSpacing:10.0 afterView:avatarHint];

    self.nameLabel = [self labelWithText:@""
                                   color:LumiTextColor()
                                    font:LumiFont(23.0, UIFontWeightBold)];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:self.nameLabel];

    self.subtitleLabel = [self labelWithText:@""
                                       color:LumiMutedColor()
                                        font:LumiFont(13.0, UIFontWeightRegular)];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:self.subtitleLabel];
    [self.stack setCustomSpacing:18.0 afterView:self.subtitleLabel];

    self.relationshipTitleLabel = [self sectionTitleWithText:@"Отношения с персонажами"];
    [self.stack addArrangedSubview:self.relationshipTitleLabel];
    self.relationshipStack = [[UIStackView alloc] init];
    self.relationshipStack.axis = UILayoutConstraintAxisVertical;
    self.relationshipStack.spacing = 12.0;
    [self.stack addArrangedSubview:self.relationshipStack];
    self.relationshipLabel = [self bodyLabel];
    [self.stack addArrangedSubview:self.relationshipLabel];
    [self.stack setCustomSpacing:18.0 afterView:self.relationshipLabel];

    self.memoryTitleLabel = [self sectionTitleWithText:@"Память"];
    [self.stack addArrangedSubview:self.memoryTitleLabel];
    self.memoryLabel = [self bodyLabel];
    [self.stack addArrangedSubview:self.memoryLabel];
    [self.stack setCustomSpacing:18.0 afterView:self.memoryLabel];

    self.aboutTitleLabel = [self sectionTitleWithText:@"Описание"];
    [self.stack addArrangedSubview:self.aboutTitleLabel];
    self.aboutLabel = [self bodyLabel];
    [self.stack addArrangedSubview:self.aboutLabel];
    [self.stack setCustomSpacing:18.0 afterView:self.aboutLabel];

    self.tagsLabel = [self labelWithText:@""
                                   color:LumiAccentColor()
                                    font:LumiFont(12.0, UIFontWeightMedium)];
    [self.stack addArrangedSubview:self.tagsLabel];
    [self.stack setCustomSpacing:20.0 afterView:self.tagsLabel];

    UIButton *appearanceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [appearanceButton setTitle:@"🎨  Цвета чата" forState:UIControlStateNormal];
    appearanceButton.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    [appearanceButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    appearanceButton.backgroundColor = [[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor();
    appearanceButton.layer.cornerRadius = 14.0;
    [appearanceButton.heightAnchor constraintEqualToConstant:50.0].active = YES;
    [appearanceButton addTarget:self action:@selector(appearanceTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:appearanceButton];

    UILabel *note = [self labelWithText:@"Изменения цветов применяются сразу и сохраняются между запусками."
                                  color:LumiMutedColor()
                                   font:LumiFont(11.0, UIFontWeightRegular)];
    note.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:note];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = [[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor();
    [self.stack addArrangedSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:18.0],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:20.0],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-20.0],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-28.0],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-40.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appearanceChanged)
                                                 name:LumiChatAppearanceDidChangeNotification
                                               object:nil];

    [self render];
    [self loadDetail];
    [self loadChat];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Helpers

- (UILabel *)labelWithText:(NSString *)text color:(UIColor *)color font:(UIFont *)font {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = color;
    label.font = font;
    label.numberOfLines = 0;
    return label;
}

- (UILabel *)sectionTitleWithText:(NSString *)text {
    return [self labelWithText:text
                         color:[[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor()
                          font:LumiFont(13.0, UIFontWeightSemibold)];
}

- (UILabel *)bodyLabel {
    return [self labelWithText:@""
                         color:LumiTextColor()
                          font:LumiFont(14.5, UIFontWeightRegular)];
}

#pragma mark - Rendering

- (void)appearanceChanged {
    UIColor *accent = [[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor();
    self.relationshipTitleLabel.textColor = accent;
    self.memoryTitleLabel.textColor = accent;
    self.aboutTitleLabel.textColor = accent;
    self.spinner.color = accent;
}

- (void)render {
    NSDictionary *resolved = self.resolved;
    BOOL isStory = self.kind == LumiDetailKindStory;
    NSString *name = isStory
        ? (LumiAsString(resolved[@"title"]) ?: LumiAsString(resolved[@"name"]))
        : (LumiAsString(resolved[@"name"]) ?: LumiAsString(resolved[@"title"]));
    self.nameLabel.text = name.length ? name : @"Без названия";

    NSString *tagline = LumiAsString(LumiValue(resolved, @"tagline"));
    NSString *owner = LumiNestedString(resolved, @"owner", @"username");
    NSMutableArray *subtitle = [NSMutableArray array];
    if (tagline.length) {
        [subtitle addObject:tagline];
    }
    if (owner.length) {
        [subtitle addObject:[@"@" stringByAppendingString:owner]];
    }
    self.subtitleLabel.text = [subtitle componentsJoinedByString:@" · "];
    self.subtitleLabel.hidden = subtitle.count == 0;

    NSString *avatar = LumiAsString(LumiValue(resolved, @"avatar_url"));
    if (avatar.length) {
        [[LumiImageLoader sharedLoader] loadURLString:avatar intoImageView:self.avatarImageView];
    }

    NSMutableArray *aboutParts = [NSMutableArray array];
    NSMutableSet *usedAbout = [NSMutableSet set];
    for (NSString *key in LumiAboutKeys()) {
        NSString *text = LumiReadableValue(resolved[key], 0);
        if (text.length && ![usedAbout containsObject:text]) {
            [usedAbout addObject:text];
            [aboutParts addObject:text];
        }
    }
    self.aboutLabel.text = aboutParts.count
        ? [aboutParts componentsJoinedByString:@"\n\n"]
        : (isStory ? @"Описание истории пока недоступно." : @"Описание персонажа пока недоступно.");
    self.aboutLabel.hidden = NO;

    NSArray *tags = LumiAsArray(resolved[@"tags"]);
    NSMutableArray *tagStrings = [NSMutableArray array];
    for (id tag in tags) {
        NSString *text = LumiAsString(tag);
        if (text.length) {
            [tagStrings addObject:[@"#" stringByAppendingString:text]];
        }
    }
    self.tagsLabel.text = [tagStrings componentsJoinedByString:@"  "];
    self.tagsLabel.hidden = tagStrings.count == 0;

    [self rebuildRelationships];
}

- (void)rebuildRelationships {
    [self.relationshipEntries removeAllObjects];
    [self.memoryEntries removeAllObjects];
    LumiCollectState(self.resolved, nil, nil, NO, self.relationshipEntries, 0);
    LumiCollectState(self.resolved, nil, nil, YES, self.memoryEntries, 0);

    // Deduplicate identical lines that the API repeats under several keys.
    NSMutableArray *relationships = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *entry in self.relationshipEntries) {
        NSString *text = LumiAsString(entry[@"text"]);
        NSString *name = LumiAsString(entry[@"name"]);
        NSString *key = [NSString stringWithFormat:@"%@|%@", name ?: @"", text ?: @""];
        if (!text.length || [seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [relationships addObject:entry];
    }

    for (UIView *view in [self.relationshipStack.arrangedSubviews copy]) {
        [self.relationshipStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    // Merge the story cast with any characters mentioned in relationship data.
    NSMutableArray<NSDictionary *> *rows = [self.castMembers mutableCopy] ?: [NSMutableArray array];
    for (NSDictionary *entry in relationships) {
        NSString *entryName = LumiAsString(entry[@"name"]);
        if (!entryName.length) {
            continue;
        }
        BOOL exists = NO;
        for (NSDictionary *row in rows) {
            if ([LumiAsString(row[@"name"]) isEqualToString:entryName]) {
                exists = YES;
                break;
            }
        }
        if (!exists) {
            [rows addObject:@{@"name": entryName, @"avatar_url": LumiAsString(entry[@"avatar_url"]) ?: @""}];
        }
    }

    BOOL isStory = self.kind == LumiDetailKindStory;
    if (rows.count == 0) {
        NSString *fallbackName = LumiAsString(self.resolved[@"name"]) ?: LumiAsString(self.resolved[@"title"]);
        if (fallbackName.length) {
            [rows addObject:@{@"name": fallbackName,
                              @"avatar_url": LumiAsString(self.resolved[@"avatar_url"]) ?: @""}];
        }
    }

    for (NSDictionary *row in rows) {
        NSString *rowName = LumiAsString(row[@"name"]);
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        NSMutableArray<NSDictionary *> *matched = [NSMutableArray array];
        for (NSDictionary *entry in relationships) {
            NSString *entryName = LumiAsString(entry[@"name"]);
            if (entryName.length && rowName.length &&
                [entryName caseInsensitiveCompare:rowName] != NSOrderedSame) {
                continue;
            }
            [matched addObject:entry];
        }
        if (matched.count == 0 && relationships.count > 0 && rows.count == 1) {
            matched = [relationships mutableCopy];
        }
        for (NSDictionary *entry in matched) {
            NSString *text = LumiAsString(entry[@"text"]);
            NSString *label = LumiAsString(entry[@"label"]);
            if (!text.length) {
                continue;
            }
            if (label.length && ![label isEqualToString:@"Отношения"]) {
                [parts addObject:[NSString stringWithFormat:@"%@: %@", label, text]];
            } else {
                [parts addObject:text];
            }
        }
        NSString *text = [parts componentsJoinedByString:@"\n"];
        BOOL isBiography = NO;
        if (!text.length) {
            NSString *condensed = LumiCondensedText(LumiAsString(row[@"description"]), rowName, 170);
            if (condensed.length) {
                text = condensed;
                isBiography = YES;
            }
        }
        UIView *rowView = [self relationshipRowWithName:rowName
                                               avatarURL:LumiAsString(row[@"avatar_url"])
                                                     text:text
                                                  isStory:isStory
                                                biography:isBiography];
        [self.relationshipStack addArrangedSubview:rowView];
    }

    if (rows.count == 0) {
        self.relationshipLabel.hidden = NO;
        self.relationshipLabel.textColor = LumiMutedColor();
        self.relationshipLabel.text = isStory
            ? @"Отношения в этой истории появятся после первого сообщения."
            : @"Здесь появятся отношения с персонажем, заметки и память о вашем общении.";
    } else if (relationships.count == 0) {
        self.relationshipLabel.hidden = NO;
        self.relationshipLabel.textColor = LumiMutedColor();
        self.relationshipLabel.text = isStory
            ? @"Отношения с персонажами появятся по мере общения в истории."
            : @"Отношения появятся по мере общения.";
    } else {
        self.relationshipLabel.hidden = YES;
        self.relationshipLabel.text = nil;
    }

    NSMutableArray<NSString *> *memoryLines = [NSMutableArray array];
    NSMutableSet *seenMemory = [NSMutableSet set];
    for (NSDictionary *entry in self.memoryEntries) {
        NSString *text = LumiAsString(entry[@"text"]);
        if (!text.length || [seenMemory containsObject:text]) {
            continue;
        }
        [seenMemory addObject:text];
        NSString *label = LumiAsString(entry[@"label"]);
        NSString *name = LumiAsString(entry[@"name"]);
        if (name.length && rows.count > 1) {
            [memoryLines addObject:[NSString stringWithFormat:@"%@ — %@", name, text]];
        } else if (label.length && ![label isEqualToString:@"Память"]) {
            [memoryLines addObject:[NSString stringWithFormat:@"%@: %@", label, text]];
        } else {
            [memoryLines addObject:text];
        }
    }
    if (memoryLines.count) {
        self.memoryTitleLabel.hidden = NO;
        self.memoryLabel.hidden = NO;
        self.memoryLabel.text = [memoryLines componentsJoinedByString:@"\n\n"];
    } else {
        self.memoryTitleLabel.hidden = YES;
        self.memoryLabel.hidden = YES;
        self.memoryLabel.text = nil;
    }

    [LumiDiagnostics log:@"О чате %@: отношения %lu, память %lu, каст %lu",
     self.targetIdentifier ?: @"?",
     (unsigned long)relationships.count,
     (unsigned long)memoryLines.count,
     (unsigned long)rows.count];
}

/// A cast row: round portrait, character name and the relationship text.
- (UIView *)relationshipRowWithName:(NSString *)name
                          avatarURL:(NSString *)avatarURL
                               text:(NSString *)text
                            isStory:(BOOL)isStory
                          biography:(BOOL)isBiography {
    UIView *container = [[UIView alloc] init];

    UIImageView *avatarView = [[UIImageView alloc] initWithFrame:CGRectZero];
    avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    avatarView.clipsToBounds = YES;
    avatarView.layer.cornerRadius = 18.0;
    avatarView.backgroundColor = LumiSurfaceColor();
    avatarView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    if (avatarURL.length) {
        [[LumiImageLoader sharedLoader] loadURLString:avatarURL intoImageView:avatarView];
    }
    [container addSubview:avatarView];

    UILabel *nameLabel = [self labelWithText:name.length ? name : @"Персонаж"
                                       color:LumiTextColor()
                                        font:LumiFont(14.0, UIFontWeightSemibold)];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:nameLabel];

    NSString *body = text.length ? text : (isStory
        ? @"Отношения формируются по мере прохождения истории."
        : @"Отношения ещё не заданы.");
    UIColor *bodyColor = (text.length && !isBiography) ? LumiTextColor() : LumiMutedColor();
    UILabel *bodyLabel = [self labelWithText:body
                                       color:bodyColor
                                        font:LumiFont(13.0, UIFontWeightRegular)];
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:bodyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [avatarView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [avatarView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [avatarView.widthAnchor constraintEqualToConstant:36.0],
        [avatarView.heightAnchor constraintEqualToConstant:36.0],

        [nameLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [nameLabel.leadingAnchor constraintEqualToAnchor:avatarView.trailingAnchor constant:10.0],
        [nameLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [bodyLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2.0],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [bodyLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [bodyLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [bodyLabel.bottomAnchor constraintGreaterThanOrEqualToAnchor:avatarView.bottomAnchor],
    ]];
    return container;
}

#pragma mark - Loading

- (void)loadDetail {
    NSString *identifier = self.targetIdentifier;
    if (!identifier.length) {
        return;
    }
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    LumiAPICompletion completion = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.spinner stopAnimating];
        NSDictionary *detail = LumiAsDictionary(result);
        if (!detail) {
            return;
        }
        [LumiDiagnostics log:@"О чате %@: поля карточки — %@",
         identifier, [[detail allKeys] componentsJoinedByString:@","]];
        [strongSelf mergePayload:detail skippingIdentifier:NO];
        [strongSelf collectCastFrom:detail];
        [strongSelf render];
    };
    if (self.kind == LumiDetailKindStory) {
        [[LumiAPI sharedClient] fetchStoryWithID:identifier completion:completion];
    } else {
        [[LumiAPI sharedClient] fetchCharacterWithID:identifier completion:completion];
    }
}

/// The chat payload carries the live relationship/memory state, so refresh it
/// as well: character details do not include per-chat progress.
- (void)loadChat {
    if (!self.chatID.length) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[LumiAPI sharedClient] fetchChatWithID:self.chatID completion:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSDictionary *payload = LumiAsDictionary(result);
        if (!payload) {
            return;
        }
        NSDictionary *chat = LumiAsDictionary(LumiValue(payload, @"chat"))
            ?: LumiAsDictionary(LumiValue(payload, @"session"))
            ?: payload;
        [LumiDiagnostics log:@"О чате %@: поля чата — %@",
         strongSelf.chatID, [[chat allKeys] componentsJoinedByString:@","]];
        [strongSelf mergePayload:chat skippingIdentifier:YES];
        [strongSelf collectCastFrom:chat];
        [strongSelf render];
    }];
}

- (void)mergePayload:(NSDictionary *)payload skippingIdentifier:(BOOL)skipIdentifier {
    for (NSString *key in payload) {
        if (skipIdentifier && [key isEqualToString:@"id"]) {
            continue;
        }
        id value = payload[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
            [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
            self.resolved[key] = value;
        }
    }
    NSDictionary *target = LumiAsDictionary(LumiValue(payload, @"target"));
    if (target) {
        for (NSString *key in target) {
            id value = target[key];
            if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
                [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                if (!self.resolved[key]) {
                    self.resolved[key] = value;
                }
            }
        }
    }
}

#pragma mark - Actions

- (void)avatarTapped {
    NSString *avatar = LumiAsString(LumiValue(self.resolved, @"avatar_url"));
    NSString *name = self.nameLabel.text;
    LumiImageViewerViewController *viewer = avatar.length
        ? [[LumiImageViewerViewController alloc] initWithImageURL:avatar title:name]
        : [[LumiImageViewerViewController alloc] initWithImage:[UIImage imageNamed:@"AvatarPlaceholder"] title:name];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)appearanceTapped {
    LumiChatAppearanceViewController *controller = [[LumiChatAppearanceViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
