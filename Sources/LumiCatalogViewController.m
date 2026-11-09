#import "LumiCatalogViewController.h"
#import "LumiAPIClient.h"
#import "LumiCharacterViewController.h"
#import "LumiImageLoader.h"
#import "LumiTheme.h"

@interface LumiCatalogCell : UITableViewCell
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureWithCharacter:(NSDictionary *)character;
@end

@implementation LumiCatalogCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = LumiSurfaceColor();
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        self.thumb = [[UIImageView alloc] init];
        self.thumb.translatesAutoresizingMaskIntoConstraints = NO;
        self.thumb.contentMode = UIViewContentModeScaleAspectFill;
        self.thumb.clipsToBounds = YES;
        self.thumb.layer.cornerRadius = 12.0;
        self.thumb.image = [UIImage imageNamed:@"AvatarPlaceholder"];
        [self.contentView addSubview:self.thumb];

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameLabel.textColor = LumiTextColor();
        self.nameLabel.font = LumiFont(16.0, UIFontWeightSemibold);
        [self.contentView addSubview:self.nameLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.textColor = LumiMutedColor();
        self.subtitleLabel.font = LumiFont(13.0, UIFontWeightRegular);
        self.subtitleLabel.numberOfLines = 2;
        [self.contentView addSubview:self.subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.thumb.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [self.thumb.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.thumb.widthAnchor constraintEqualToConstant:60.0],
            [self.thumb.heightAnchor constraintEqualToConstant:60.0],
            [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.thumb.trailingAnchor constant:14.0],
            [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
            [self.nameLabel.topAnchor constraintEqualToAnchor:self.thumb.topAnchor constant:2.0],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4.0],
        ]];
    }
    return self;
}

- (void)configureWithCharacter:(NSDictionary *)character {
    self.nameLabel.text = character[@"name"];
    self.subtitleLabel.text = character[@"title"];
    [[LumiImageLoader sharedLoader] loadURLString:character[@"avatar"] intoImageView:self.thumb];
}

@end

@interface LumiCatalogViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) NSArray<NSDictionary *> *characters;
@end

@implementation LumiCatalogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 84.0;
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 16, 0);
    [self.tableView registerClass:[LumiCatalogCell class] forCellReuseIdentifier:@"character"];
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = LumiMutedColor();
    [self.refreshControl addTarget:self action:@selector(loadCatalog) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.textColor = LumiMutedColor();
    self.stateLabel.font = LumiFont(15.0, UIFontWeightRegular);
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.numberOfLines = 0;
    self.stateLabel.hidden = YES;
    [self.view addSubview:self.stateLabel];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.stateLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.stateLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.stateLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:32.0],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-32.0],
    ]];

    [self loadCatalog];
}

- (void)loadCatalog {
    [self.spinner startAnimating];
    self.stateLabel.hidden = YES;

    [[LumiAPIClient sharedClient] fetchCatalogWithCompletion:^(NSDictionary *json, NSError *error) {
        [self.spinner stopAnimating];
        [self.refreshControl endRefreshing];

        if (error) {
            self.stateLabel.text = [NSString stringWithFormat:@"Не удалось загрузить каталог.\n%@", error.localizedDescription];
            self.stateLabel.hidden = NO;
            return;
        }

        NSArray *items = json[@"items"];
        if (![items isKindOfClass:[NSArray class]]) {
            items = json[@"results"];
        }
        NSMutableArray *characters = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *partner = item[@"partner"];
            if (![partner isKindOfClass:[NSDictionary class]] || ![partner[@"kind"] isEqual:@"character"]) {
                continue;
            }
            NSString *identifier = partner[@"id"];
            if (!identifier.length || [seen containsObject:identifier]) {
                continue;
            }
            [seen addObject:identifier];
            [characters addObject:@{
                @"id": identifier,
                @"name": partner[@"name"] ?: @"Персонаж",
                @"avatar": partner[@"avatar_url"] ?: @"",
                @"title": item[@"title"] ?: @"",
            }];
        }
        self.characters = characters;
        [self.tableView reloadData];
        if (!characters.count) {
            self.stateLabel.text = @"Каталог пуст. Потяните вниз, чтобы обновить.";
            self.stateLabel.hidden = NO;
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.characters.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LumiCatalogCell *cell = [tableView dequeueReusableCellWithIdentifier:@"character" forIndexPath:indexPath];
    [cell configureWithCharacter:self.characters[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *character = self.characters[indexPath.row];
    LumiCharacterViewController *detail = [[LumiCharacterViewController alloc] initWithCharacterID:character[@"id"]
                                                                                            name:character[@"name"]
                                                                                          avatar:character[@"avatar"]];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
