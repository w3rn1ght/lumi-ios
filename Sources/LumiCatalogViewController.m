#import "LumiCatalogViewController.h"
#import "LumiCatalogStore.h"
#import "LumiDetailViewController.h"
#import "LumiImageLoader.h"
#import "LumiTheme.h"

typedef NS_ENUM(NSInteger, LumiCatalogMode) {
    LumiCatalogModeCharacters = 0,
    LumiCatalogModeStories = 1,
};

@interface LumiCatalogCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UILabel *countLabel;
- (void)configureWithCharacter:(NSDictionary *)character;
- (void)configureWithStory:(NSDictionary *)story;
@end

@implementation LumiCatalogCell

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
        self.thumb.layer.cornerRadius = 14.0;
        self.thumb.backgroundColor = LumiSurfaceColor();
        self.thumb.image = [UIImage imageNamed:@"AvatarPlaceholder"];
        [self.contentView addSubview:self.thumb];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
        self.titleLabel.textColor = LumiTextColor();
        self.titleLabel.numberOfLines = 1;
        [self.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.font = LumiFont(13.0, UIFontWeightRegular);
        self.subtitleLabel.textColor = LumiMutedColor();
        self.subtitleLabel.numberOfLines = 2;
        [self.contentView addSubview:self.subtitleLabel];

        self.tagsLabel = [[UILabel alloc] init];
        self.tagsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.tagsLabel.font = LumiFont(11.0, UIFontWeightMedium);
        self.tagsLabel.textColor = LumiAccentColor();
        self.tagsLabel.numberOfLines = 1;
        [self.contentView addSubview:self.tagsLabel];

        self.countLabel = [[UILabel alloc] init];
        self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.countLabel.font = LumiFont(11.0, UIFontWeightRegular);
        self.countLabel.textColor = LumiMutedColor();
        self.countLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [self.thumb.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.thumb.widthAnchor constraintEqualToConstant:72.0],
            [self.thumb.heightAnchor constraintEqualToConstant:72.0],

            [self.titleLabel.topAnchor constraintEqualToAnchor:self.thumb.topAnchor],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:12.0],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.countLabel.leadingAnchor constant:-6.0],

            [self.countLabel.topAnchor constraintEqualToAnchor:self.thumb.topAnchor constant:2.0],
            [self.countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [self.countLabel.widthAnchor constraintEqualToConstant:64.0],

            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:3.0],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [self.tagsLabel.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:4.0],
            [self.tagsLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.tagsLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        ]];
    }
    return self;
}

- (void)configureWithCharacter:(NSDictionary *)character {
    self.titleLabel.text = character[@"name"] ?: @"Персонаж";
    NSString *tagline = character[@"tagline"];
    self.subtitleLabel.text = tagline.length ? tagline : ([character[@"tags"] isKindOfClass:[NSArray class]]
                                                         ? [character[@"tags"] componentsJoinedByString:@" · "] : @"");
    NSArray *tags = character[@"tags"];
    self.tagsLabel.text = [self tagLineFromTags:tags skipFirst:tagline.length > 0];
    NSNumber *count = character[@"message_count"];
    self.countLabel.text = count ? [self formatCount:count.integerValue] : @"";
    [self.thumb setImage:nil];
    [[LumiImageLoader sharedLoader] loadURLString:character[@"avatar_url"] intoImageView:self.thumb];
}

- (void)configureWithStory:(NSDictionary *)story {
    self.titleLabel.text = story[@"title"] ?: @"История";
    NSString *description = story[@"description"];
    self.subtitleLabel.text = description.length ? description : @"";
    self.tagsLabel.text = [self tagLineFromTags:story[@"tags"] skipFirst:NO];
    NSNumber *count = story[@"message_count"];
    self.countLabel.text = count ? [self formatCount:count.integerValue] : @"";
    [self.thumb setImage:nil];
    [[LumiImageLoader sharedLoader] loadURLString:story[@"avatar_url"] intoImageView:self.thumb];
}

- (NSString *)tagLineFromTags:(NSArray *)tags skipFirst:(BOOL)skipFirst {
    if (![tags isKindOfClass:[NSArray class]] || !tags.count) {
        return @"";
    }
    NSMutableArray *display = [NSMutableArray array];
    for (NSString *tag in tags) {
        if (![tag isKindOfClass:[NSString class]]) {
            continue;
        }
        [display addObject:[@"#" stringByAppendingString:tag]];
        if (display.count == 3) {
            break;
        }
    }
    return [display componentsJoinedByString:@"  "];
}

- (NSString *)formatCount:(NSInteger)count {
    if (count < 1000) {
        return [NSString stringWithFormat:@"%ld", (long)count];
    }
    if (count < 1000000) {
        return [NSString stringWithFormat:@"%.1fk", count / 1000.0];
    }
    return [NSString stringWithFormat:@"%.1fm", count / 1000000.0];
}

@end

#pragma mark - Catalog

@interface LumiCatalogViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) LumiCatalogStore *store;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *chipsScrollView;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSString *selectedTag;
@property (nonatomic, copy) NSArray<NSDictionary *> *items;
@property (nonatomic, assign) LumiCatalogMode mode;
@end

@implementation LumiCatalogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = @"Каталог";
    self.store = [LumiCatalogStore sharedStore];
    self.selectedTag = @"Все";
    self.items = @[];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Персонажи", @"Истории"]];
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.tintColor = LumiAccentColor();
    [self.segmentedControl addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"Поиск персонажей";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.tintColor = LumiAccentColor();
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.barTintColor = LumiSurfaceColor();
    self.searchBar.backgroundColor = LumiSurfaceColor();
    self.searchBar.layer.cornerRadius = 12.0;
    self.searchBar.clipsToBounds = YES;
    UITextField *searchField = [self.searchBar valueForKey:@"searchField"];
    if ([searchField isKindOfClass:[UITextField class]]) {
        searchField.textColor = LumiTextColor();
        searchField.backgroundColor = UIColor.clearColor;
        searchField.font = LumiFont(15.0, UIFontWeightRegular);
    }

    self.chipsScrollView = [[UIScrollView alloc] init];
    self.chipsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipsScrollView.showsHorizontalScrollIndicator = NO;
    self.chipsScrollView.alwaysBounceHorizontal = YES;

    self.chipsStack = [[UIStackView alloc] init];
    self.chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.chipsStack.axis = UILayoutConstraintAxisHorizontal;
    self.chipsStack.spacing = 8.0;
    self.chipsStack.alignment = UIStackViewAlignmentCenter;
    [self.chipsScrollView addSubview:self.chipsStack];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24.0, 0);
    [self.tableView registerClass:[LumiCatalogCell class] forCellReuseIdentifier:@"character"];
    [self.tableView registerClass:[LumiCatalogCell class] forCellReuseIdentifier:@"story"];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    refreshControl.tintColor = LumiAccentColor();
    [refreshControl addTarget:self action:@selector(refreshPulled) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refreshControl;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = LumiFont(12.0, UIFontWeightRegular);
    self.statusLabel.textColor = LumiMutedColor();
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = LumiAccentColor();
    self.spinner.hidesWhenStopped = YES;

    [self.view addSubview:self.segmentedControl];
    [self.view addSubview:self.searchBar];
    [self.view addSubview:self.chipsScrollView];
    [self.view addSubview:self.tableView];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.segmentedControl.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8.0],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:32.0],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:8.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8.0],
        [self.searchBar.heightAnchor constraintEqualToConstant:44.0],

        [self.chipsScrollView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:6.0],
        [self.chipsScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.chipsScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.chipsScrollView.heightAnchor constraintEqualToConstant:36.0],

        [self.chipsStack.leadingAnchor constraintEqualToAnchor:self.chipsScrollView.leadingAnchor constant:16.0],
        [self.chipsStack.trailingAnchor constraintEqualToAnchor:self.chipsScrollView.trailingAnchor constant:-16.0],
        [self.chipsStack.topAnchor constraintEqualToAnchor:self.chipsScrollView.topAnchor],
        [self.chipsStack.bottomAnchor constraintEqualToAnchor:self.chipsScrollView.bottomAnchor],
        [self.chipsStack.heightAnchor constraintEqualToAnchor:self.chipsScrollView.heightAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.chipsScrollView.bottomAnchor constant:6.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(catalogUpdated)
                                                 name:LumiCatalogDidUpdateNotification
                                               object:nil];

    [self rebuildChips];
    [self reloadItems];
    [[LumiCatalogStore sharedStore] startIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadItems];
    [[LumiCatalogStore sharedStore] refreshInBackgroundIfStale];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Data

- (void)modeChanged {
    self.mode = self.segmentedControl.selectedSegmentIndex == 1 ? LumiCatalogModeStories : LumiCatalogModeCharacters;
    self.selectedTag = @"Все";
    self.searchBar.placeholder = self.mode == LumiCatalogModeStories ? @"Поиск историй" : @"Поиск персонажей";
    [self rebuildChips];
    [self reloadItems];
}

- (void)rebuildChips {
    for (UIView *view in self.chipsStack.arrangedSubviews.copy) {
        [self.chipsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<NSString *> *genres = self.mode == LumiCatalogModeStories
        ? [LumiCatalogStore storyGenres]
        : [LumiCatalogStore characterGenres];
    for (NSString *genre in genres) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:genre forState:UIControlStateNormal];
        chip.titleLabel.font = LumiFont(13.0, UIFontWeightMedium);
        chip.layer.cornerRadius = 14.0;
        chip.contentEdgeInsets = UIEdgeInsetsMake(6.0, 14.0, 6.0, 14.0);
        chip.tag = [genres indexOfObject:genre];
        BOOL selected = [genre isEqualToString:self.selectedTag];
        chip.backgroundColor = selected ? LumiAccentColor() : LumiSurfaceColor();
        [chip setTitleColor:selected ? [UIColor whiteColor] : LumiMutedColor() forState:UIControlStateNormal];
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.chipsStack addArrangedSubview:chip];
    }
}

- (void)refreshPulled {
    [[LumiCatalogStore sharedStore] forceRefresh];
    [self reloadItems];
}

- (void)chipTapped:(UIButton *)sender {    NSArray<NSString *> *genres = self.mode == LumiCatalogModeStories
        ? [LumiCatalogStore storyGenres]
        : [LumiCatalogStore characterGenres];
    if (sender.tag < 0 || sender.tag >= (NSInteger)genres.count) {
        return;
    }
    self.selectedTag = genres[sender.tag];
    [self rebuildChips];
    [self reloadItems];
}

- (void)catalogUpdated {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadItems];
    });
}

- (void)reloadItems {
    NSString *query = self.searchBar.text ?: @"";
    if (self.mode == LumiCatalogModeStories) {
        self.items = [self.store storiesMatchingQuery:query tag:self.selectedTag];
    } else {
        self.items = [self.store charactersMatchingQuery:query tag:self.selectedTag];
    }
    [self.tableView reloadData];

    BOOL syncing = self.store.isSyncing;
    NSString *status = nil;
    if (syncing) {
        status = self.store.syncStatus ?: @"Загрузка каталога…";
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
        if (!self.items.count) {
            status = self.store.characters.count
                ? @"Ничего не найдено. Попробуйте другой запрос или жанр."
                : @"Каталог пуст. Потяните вниз, чтобы повторить загрузку.";
        } else {
            status = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.items.count,
                      self.mode == LumiCatalogModeStories ? @"историй" : @"персонажей"];
        }
    }
    self.statusLabel.text = status;
    [self.tableView.refreshControl endRefreshing];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 96.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isStory = self.mode == LumiCatalogModeStories;
    LumiCatalogCell *cell = [tableView dequeueReusableCellWithIdentifier:(isStory ? @"story" : @"character")];
    NSDictionary *item = self.items[indexPath.row];
    if (isStory) {
        [cell configureWithStory:item];
    } else {
        [cell configureWithCharacter:item];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.items[indexPath.row];
    LumiDetailViewController *detail = [[LumiDetailViewController alloc] initWithItem:item
                                                                                kind:(self.mode == LumiCatalogModeStories
                                                                                      ? LumiDetailKindStory
                                                                                      : LumiDetailKindCharacter)];
    [self.navigationController pushViewController:detail animated:YES];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self reloadItems];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    [self reloadItems];
}

@end
