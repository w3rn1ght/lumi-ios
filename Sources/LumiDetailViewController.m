#import "LumiDetailViewController.h"
#import "LumiAPI.h"
#import "LumiChatViewController.h"
#import "LumiImageLoader.h"
#import "LumiLoginViewController.h"
#import "LumiTheme.h"

@interface LumiDetailViewController ()
@property (nonatomic, strong) NSMutableDictionary *item;
@property (nonatomic, assign) LumiDetailKind kind;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIImageView *headerImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIStackView *castStack;
@property (nonatomic, strong) UILabel *castTitleLabel;
@property (nonatomic, assign) BOOL loadingDetail;
@end

@implementation LumiDetailViewController

- (instancetype)initWithItem:(NSDictionary *)item kind:(LumiDetailKind)kind {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _item = [item mutableCopy] ?: [NSMutableDictionary dictionary];
        _kind = kind;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = self.kind == LumiDetailKindStory ? @"История" : @"Персонаж";

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.stack = [[UIStackView alloc] init];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12.0;
    [self.scrollView addSubview:self.stack];

    self.headerImageView = [[UIImageView alloc] init];
    self.headerImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.headerImageView.clipsToBounds = YES;
    self.headerImageView.layer.cornerRadius = 18.0;
    self.headerImageView.backgroundColor = LumiSurfaceColor();
    self.headerImageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    [self.stack addArrangedSubview:self.headerImageView];
    [self.headerImageView.heightAnchor constraintEqualToConstant:280.0].active = YES;

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = LumiFont(24.0, UIFontWeightBold);
    self.titleLabel.textColor = LumiTextColor();
    self.titleLabel.numberOfLines = 0;

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = LumiFont(14.0, UIFontWeightRegular);
    self.subtitleLabel.textColor = LumiMutedColor();
    self.subtitleLabel.numberOfLines = 0;

    self.tagsLabel = [[UILabel alloc] init];
    self.tagsLabel.font = LumiFont(12.0, UIFontWeightMedium);
    self.tagsLabel.textColor = LumiAccentColor();
    self.tagsLabel.numberOfLines = 0;

    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:(self.kind == LumiDetailKindStory ? @"Начать историю" : @"Начать чат")
                      forState:UIControlStateNormal];
    self.startButton.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = LumiAccentColor();
    self.startButton.layer.cornerRadius = 14.0;
    [self.startButton addTarget:self action:@selector(startChatTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.startButton.heightAnchor constraintEqualToConstant:52.0].active = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = LumiAccentColor();

    self.bodyLabel = [[UILabel alloc] init];
    self.bodyLabel.font = LumiFont(15.0, UIFontWeightRegular);
    self.bodyLabel.textColor = LumiTextColor();
    self.bodyLabel.numberOfLines = 0;

    self.castTitleLabel = [[UILabel alloc] init];
    self.castTitleLabel.text = @"Персонажи истории";
    self.castTitleLabel.font = LumiFont(17.0, UIFontWeightSemibold);
    self.castTitleLabel.textColor = LumiTextColor();

    self.castStack = [[UIStackView alloc] init];
    self.castStack.axis = UILayoutConstraintAxisHorizontal;
    self.castStack.spacing = 12.0;

    [self.stack addArrangedSubview:self.titleLabel];
    [self.stack addArrangedSubview:self.subtitleLabel];
    [self.stack addArrangedSubview:self.tagsLabel];
    [self.stack addArrangedSubview:self.startButton];
    [self.stack addArrangedSubview:self.spinner];
    [self.stack addArrangedSubview:self.bodyLabel];
    [self.stack addArrangedSubview:self.castTitleLabel];

    UIScrollView *castScroll = [[UIScrollView alloc] init];
    castScroll.showsHorizontalScrollIndicator = NO;
    [castScroll.heightAnchor constraintEqualToConstant:120.0].active = YES;
    [castScroll addSubview:self.castStack];
    self.castStack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.castStack.leadingAnchor constraintEqualToAnchor:castScroll.leadingAnchor],
        [self.castStack.trailingAnchor constraintEqualToAnchor:castScroll.trailingAnchor],
        [self.castStack.topAnchor constraintEqualToAnchor:castScroll.topAnchor],
        [self.castStack.bottomAnchor constraintEqualToAnchor:castScroll.bottomAnchor],
        [self.castStack.heightAnchor constraintEqualToAnchor:castScroll.heightAnchor],
    ]];
    [self.stack addArrangedSubview:castScroll];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16.0],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16.0],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16.0],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24.0],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32.0],
    ]];

    [self applyItem];
    [self loadFullDetail];
}

#pragma mark - Rendering

- (void)applyItem {
    NSString *primary = self.kind == LumiDetailKindStory ? self.item[@"title"] : self.item[@"name"];
    self.titleLabel.text = primary ?: (self.kind == LumiDetailKindStory ? @"История" : @"Персонаж");

    if (self.kind == LumiDetailKindStory) {
        NSString *description = self.item[@"description"];
        self.subtitleLabel.text = description.length ? @"" : @"История с несколькими персонажами";
        if (description.length) {
            self.bodyLabel.text = description;
        }
    } else {
        NSString *tagline = self.item[@"tagline"];
        NSString *owner = self.item[@"owner"][@"username"];
        NSMutableArray *pieces = [NSMutableArray array];
        if (tagline.length) {
            [pieces addObject:tagline];
        }
        if (owner.length) {
            [pieces addObject:[@"@" stringByAppendingString:owner]];
        }
        self.subtitleLabel.text = [pieces componentsJoinedByString:@" · "];
    }

    NSArray *tags = self.item[@"tags"];
    if ([tags isKindOfClass:[NSArray class]] && tags.count) {
        NSMutableArray *display = [NSMutableArray array];
        for (NSString *tag in tags) {
            if ([tag isKindOfClass:[NSString class]]) {
                [display addObject:[@"#" stringByAppendingString:tag]];
            }
        }
        self.tagsLabel.text = [display componentsJoinedByString:@"  "];
    } else {
        self.tagsLabel.text = nil;
    }

    [[LumiImageLoader sharedLoader] loadURLString:self.item[@"avatar_url"] intoImageView:self.headerImageView];
    [self renderCast];
}

- (void)renderCast {
    for (UIView *view in self.castStack.arrangedSubviews.copy) {
        [self.castStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray *cast = self.item[@"cast"];
    BOOL hasCast = [cast isKindOfClass:[NSArray class]] && cast.count > 0;
    self.castTitleLabel.hidden = !hasCast;
    self.castStack.superview.hidden = !hasCast;
    if (!hasCast) {
        return;
    }
    for (NSDictionary *member in cast) {
        UIView *container = [[UIView alloc] init];
        [container.widthAnchor constraintEqualToConstant:84.0].active = YES;

        UIImageView *avatar = [[UIImageView alloc] init];
        avatar.translatesAutoresizingMaskIntoConstraints = NO;
        avatar.contentMode = UIViewContentModeScaleAspectFill;
        avatar.clipsToBounds = YES;
        avatar.layer.cornerRadius = 32.0;
        avatar.backgroundColor = LumiSurfaceColor();
        avatar.image = [UIImage imageNamed:@"AvatarPlaceholder"];
        [container addSubview:avatar];

        UILabel *name = [[UILabel alloc] init];
        name.translatesAutoresizingMaskIntoConstraints = NO;
        name.font = LumiFont(11.0, UIFontWeightMedium);
        name.textColor = LumiMutedColor();
        name.textAlignment = NSTextAlignmentCenter;
        name.numberOfLines = 2;
        name.text = member[@"name"];
        [container addSubview:name];

        [NSLayoutConstraint activateConstraints:@[
            [avatar.topAnchor constraintEqualToAnchor:container.topAnchor],
            [avatar.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
            [avatar.widthAnchor constraintEqualToConstant:64.0],
            [avatar.heightAnchor constraintEqualToConstant:64.0],
            [name.topAnchor constraintEqualToAnchor:avatar.bottomAnchor constant:6.0],
            [name.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [name.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        ]];

        [[LumiImageLoader sharedLoader] loadURLString:member[@"avatar_url"] intoImageView:avatar];
        [self.castStack addArrangedSubview:container];
    }
}

#pragma mark - Detail loading

- (void)loadFullDetail {
    NSString *identifier = self.item[@"id"];
    if (![identifier isKindOfClass:[NSString class]] || self.loadingDetail) {
        return;
    }
    self.loadingDetail = YES;
    LumiAPI *api = [LumiAPI sharedClient];
    void (^handler)(id, NSError *) = ^(id result, NSError *error) {
        self.loadingDetail = NO;
        if (![result isKindOfClass:[NSDictionary class]]) {
            return;
        }
        NSDictionary *detail = result;
        for (NSString *key in detail) {
            if ([detail[key] isKindOfClass:[NSString class]] || [detail[key] isKindOfClass:[NSArray class]] ||
                [detail[key] isKindOfClass:[NSNumber class]]) {
                self.item[key] = detail[key];
            }
        }
        if ([detail[@"cast_members"] isKindOfClass:[NSArray class]]) {
            NSMutableArray *cast = [NSMutableArray array];
            for (NSDictionary *member in detail[@"cast_members"]) {
                if ([member isKindOfClass:[NSDictionary class]] && member[@"name"]) {
                    [cast addObject:member];
                }
            }
            self.item[@"cast"] = cast;
        }
        [self applyItem];
        NSString *body = self.kind == LumiDetailKindStory ? detail[@"description"] : detail[@"backstory"];
        if ([body isKindOfClass:[NSString class]] && body.length) {
            self.bodyLabel.text = body;
        }
        if ([detail[@"tags"] isKindOfClass:[NSArray class]]) {
            self.tagsLabel.text = nil;
            [self applyItem];
        }
        if (self.kind == LumiDetailKindCharacter && [detail[@"first_message"] isKindOfClass:[NSString class]]) {
            self.item[@"first_message"] = detail[@"first_message"];
        }
    };
    if (self.kind == LumiDetailKindStory) {
        [api fetchStoryWithID:identifier completion:handler];
    } else {
        [api fetchCharacterWithID:identifier completion:handler];
    }
}

#pragma mark - Actions

- (void)startChatTapped {
    if (![[LumiAPI sharedClient] isAuthenticated]) {
        [self presentLogin];
        return;
    }
    NSString *identifier = self.item[@"id"];
    if (![identifier isKindOfClass:[NSString class]]) {
        return;
    }
    self.startButton.enabled = NO;
    self.startButton.alpha = 0.6;
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    LumiAPI *api = [LumiAPI sharedClient];
    LumiAPICompletion completion = ^(id result, NSError *error) {
        [weakSelf.spinner stopAnimating];
        weakSelf.startButton.enabled = YES;
        weakSelf.startButton.alpha = 1.0;
        if (error || ![result isKindOfClass:[NSDictionary class]]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Не удалось открыть чат"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        NSDictionary *chat = result;
        LumiChatViewController *controller = [[LumiChatViewController alloc] initWithChat:chat
                                                                                     item:weakSelf.item
                                                                                     kind:weakSelf.kind];
        [weakSelf.navigationController pushViewController:controller animated:YES];
    };
    if (self.kind == LumiDetailKindStory) {
        [api openChatWithCharacterID:nil storyID:identifier completion:completion];
    } else {
        [api openChatWithCharacterID:identifier storyID:nil completion:completion];
    }
}

- (void)presentLogin {
    LumiLoginViewController *login = [[LumiLoginViewController alloc] init];
    login.completion = ^{
        [self startChatTapped];
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:login];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    [self presentViewController:navigation animated:YES completion:nil];
}

@end
