#import "LumiChatInfoViewController.h"
#import "LumiAPI.h"
#import "LumiChatAppearance.h"
#import "LumiChatAppearanceViewController.h"
#import "LumiImageLoader.h"
#import "LumiImageViewerViewController.h"
#import "LumiSafe.h"
#import "LumiTheme.h"

static NSArray<NSString *> *LumiRelationshipKeys(void) {
    return @[@"relationship", @"relationship_description", @"user_relationship",
             @"relationship_state", @"relationship_status", @"relationship_level",
             @"relationship_level_name", @"affection", @"affection_level", @"affinity",
             @"trust", @"trust_level", @"user_notes", @"notes", @"memory", @"memories",
             @"summary", @"user_summary", @"character_summary", @"chat_summary", @"status"];
}

static NSArray<NSString *> *LumiAboutKeys(void) {
    return @[@"description", @"backstory", @"personality", @"scenario", @"appearance", @"greeting"];
}

static NSString *LumiHumanizedKey(NSString *key) {
    NSDictionary *labels = @{
        @"relationship": @"Отношения",
        @"relationship_description": @"Отношения",
        @"user_relationship": @"Ваши отношения",
        @"relationship_state": @"Состояние отношений",
        @"relationship_status": @"Статус отношений",
        @"relationship_level": @"Уровень отношений",
        @"relationship_level_name": @"Уровень отношений",
        @"affection": @"Привязанность",
        @"affection_level": @"Привязанность",
        @"affinity": @"Симпатия",
        @"trust": @"Доверие",
        @"trust_level": @"Доверие",
        @"user_notes": @"Заметки",
        @"notes": @"Заметки",
        @"memory": @"Память",
        @"memories": @"Память",
        @"summary": @"Кратко",
        @"user_summary": @"О вас",
        @"character_summary": @"О персонаже",
        @"chat_summary": @"О переписке",
        @"status": @"Статус",
        @"description": @"Описание",
        @"backstory": @"Предыстория",
        @"personality": @"Характер",
        @"scenario": @"Сценарий",
        @"appearance": @"Внешность",
        @"greeting": @"Приветствие",
        @"level": @"Уровень",
        @"value": @"Значение",
        @"name": @"Название",
        @"title": @"Заголовок",
    };
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

@interface LumiChatInfoViewController ()
@property (nonatomic, strong) NSMutableDictionary *resolved;
@property (nonatomic, assign) LumiDetailKind kind;
@property (nonatomic, copy, nullable) NSString *targetIdentifier;
@property (nonatomic, copy, nullable) NSString *chatID;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *relationshipTitleLabel;
@property (nonatomic, strong) UILabel *relationshipLabel;
@property (nonatomic, strong) UILabel *aboutTitleLabel;
@property (nonatomic, strong) UILabel *aboutLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation LumiChatInfoViewController

- (instancetype)initWithChat:(NSDictionary *)chat
                        item:(NSDictionary *)item
                        kind:(LumiDetailKind)kind {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _kind = kind;
        _resolved = [NSMutableDictionary dictionary];
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
    }
    return self;
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
    self.avatarButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarButton.imageView.clipsToBounds = YES;
    self.avatarButton.layer.cornerRadius = 54.0;
    self.avatarButton.clipsToBounds = YES;
    self.avatarButton.backgroundColor = LumiSurfaceColor();
    [self.avatarButton setImage:[UIImage imageNamed:@"AvatarPlaceholder"] forState:UIControlStateNormal];
    [self.avatarButton addTarget:self action:@selector(avatarTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.avatarButton.widthAnchor constraintEqualToConstant:108.0].active = YES;
    [self.avatarButton.heightAnchor constraintEqualToConstant:108.0].active = YES;

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

    self.relationshipTitleLabel = [self sectionTitleWithText:@"Отношения с персонажем"];
    [self.stack addArrangedSubview:self.relationshipTitleLabel];
    self.relationshipLabel = [self bodyLabel];
    [self.stack addArrangedSubview:self.relationshipLabel];
    [self.stack setCustomSpacing:18.0 afterView:self.relationshipLabel];

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
    self.relationshipTitleLabel.textColor = [[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor();
    self.aboutTitleLabel.textColor = [[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor();
    self.spinner.color = [[LumiChatAppearance sharedAppearance] boldColor] ?: LumiAccentColor();
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
        [[LumiImageLoader sharedLoader] loadURLString:avatar intoImageView:self.avatarButton.imageView];
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

    NSMutableArray *relationshipParts = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *key in LumiRelationshipKeys()) {
        id value = resolved[key];
        NSString *text = LumiReadableValue(value, 0);
        if (!text.length || [usedAbout containsObject:text] || [seen containsObject:text]) {
            continue;
        }
        [seen addObject:text];
        NSString *label = LumiHumanizedKey(key);
        BOOL keyIsLabel = [label isEqualToString:@"Отношения"] || [label isEqualToString:@"Заметки"] ||
                          [label isEqualToString:@"Память"] || [label isEqualToString:@"Кратко"] ||
                          [label isEqualToString:@"О вас"] || [label isEqualToString:@"О персонаже"] ||
                          [label isEqualToString:@"О переписке"];
        [relationshipParts addObject:keyIsLabel ? text : [NSString stringWithFormat:@"%@: %@", label, text]];
    }
    if (relationshipParts.count) {
        self.relationshipTitleLabel.hidden = NO;
        self.relationshipLabel.hidden = NO;
        self.relationshipLabel.textColor = LumiTextColor();
        self.relationshipLabel.text = [relationshipParts componentsJoinedByString:@"\n"];
    } else {
        self.relationshipTitleLabel.hidden = NO;
        self.relationshipLabel.hidden = NO;
        self.relationshipLabel.textColor = LumiMutedColor();
        self.relationshipLabel.text = isStory
            ? @"Отношения в истории формируются по мере прохождения."
            : @"Здесь появятся отношения с персонажем, заметки и память о вашем общении.";
    }

    NSArray *tags = LumiAsArray(resolved[@"tags"]);
    NSMutableArray *tagStrings = [NSMutableArray array];
    for (id tag in tags) {
        NSString *text = LumiAsString(tag);
        if (text.length) {
            [tagStrings addObject:[@"#" stringByAppendingString:text]];
        }
    }
    NSArray *cast = LumiAsArray(resolved[@"cast_members"]) ?: LumiAsArray(resolved[@"cast"]);
    if (cast.count) {
        NSMutableArray *names = [NSMutableArray array];
        for (id member in cast) {
            NSString *memberName = LumiAsString(LumiValue(member, @"name"));
            if (memberName.length) {
                [names addObject:memberName];
            }
        }
        if (names.count) {
            [tagStrings addObject:[NSString stringWithFormat:@"В истории: %@", [names componentsJoinedByString:@", "]]];
        }
    }
    self.tagsLabel.text = [tagStrings componentsJoinedByString:@"  "];
    self.tagsLabel.hidden = tagStrings.count == 0;
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
        for (NSString *key in detail) {
            id value = detail[key];
            if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
                [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                strongSelf.resolved[key] = value;
            }
        }
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
        NSDictionary *target = LumiAsDictionary(LumiValue(chat, @"target")) ?: @{};
        for (NSDictionary *source in @[chat, target]) {
            for (NSString *key in source) {
                if ([key isEqualToString:@"id"]) {
                    continue;
                }
                id value = source[key];
                if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
                    [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
                    strongSelf.resolved[key] = value;
                }
            }
        }
        [strongSelf render];
    }];
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
