#import "LumiChatAppearanceViewController.h"
#import "LumiChatAppearance.h"
#import "LumiRichText.h"
#import "LumiSafe.h"
#import "LumiTheme.h"

static UIImage *LumiCircleImage(UIColor *color, CGFloat diameter, BOOL bordered) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(diameter, diameter), NO, 0.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1.0, 1.0, diameter - 2.0, diameter - 2.0)];
    [color setFill];
    [path fill];
    if (bordered) {
        [path setLineWidth:1.0];
        [[UIColor colorWithWhite:1.0 alpha:0.25] setStroke];
        [path stroke];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Swatch picker

@interface LumiColorPickerViewController : UIViewController
@property (nonatomic, copy) void (^selectionHandler)(UIColor *color);
@property (nonatomic, copy, nullable) NSString *elementName;
@property (nonatomic, strong, nullable) UIColor *selectedColor;
@end

@implementation LumiColorPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();
    self.title = self.elementName ?: @"Цвет";

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIStackView *rows = [[UIStackView alloc] init];
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 14.0;
    rows.alignment = UIStackViewAlignmentFill;
    [scrollView addSubview:rows];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"Выберите цвет — он сразу применится в чате.";
    hint.textColor = LumiMutedColor();
    hint.font = LumiFont(13.0, UIFontWeightRegular);
    hint.numberOfLines = 0;
    [rows addArrangedSubview:hint];

    NSArray<UIColor *> *palette = [LumiChatAppearance paletteColors];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    const NSUInteger perRow = 5;
    for (NSUInteger index = 0; index < palette.count; index += perRow) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8.0;
        row.distribution = UIStackViewDistributionEqualSpacing;
        row.alignment = UIStackViewAlignmentCenter;
        NSUInteger end = MIN(index + perRow, palette.count);
        for (NSUInteger swatch = index; swatch < end; swatch++) {
            UIColor *color = palette[swatch];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.backgroundColor = color;
            button.layer.cornerRadius = 24.0;
            button.tag = (NSInteger)swatch;
            button.layer.borderWidth = 1.0;
            button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
            [button.widthAnchor constraintEqualToConstant:48.0].active = YES;
            [button.heightAnchor constraintEqualToConstant:48.0].active = YES;
            [button addTarget:self action:@selector(swatchTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
            [buttons addObject:button];
        }
        [rows addArrangedSubview:row];
    }

    UILabel *currentLabel = [[UILabel alloc] init];
    currentLabel.text = @"Текущий цвет";
    currentLabel.textColor = LumiMutedColor();
    currentLabel.font = LumiFont(12.0, UIFontWeightRegular);
    [rows addArrangedSubview:currentLabel];

    UIView *current = [[UIView alloc] init];
    current.backgroundColor = self.selectedColor ?: LumiAccentColor();
    current.layer.cornerRadius = 10.0;
    current.layer.borderWidth = 1.0;
    current.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    [current.heightAnchor constraintEqualToConstant:44.0].active = YES;
    [rows addArrangedSubview:current];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [rows.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:18.0],
        [rows.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:18.0],
        [rows.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-18.0],
        [rows.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-24.0],
        [rows.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-36.0],
    ]];
}

- (void)swatchTapped:(UIButton *)sender {
    NSArray<UIColor *> *palette = [LumiChatAppearance paletteColors];
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)palette.count) {
        return;
    }
    if (self.selectionHandler) {
        self.selectionHandler(palette[index]);
    }
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

#pragma mark - Appearance screen

@interface LumiChatAppearanceViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *previewHeader;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, copy) NSArray<NSString *> *keys;
- (void)buildPreviewHeader;
- (void)refreshPreview;
- (void)appearanceChanged;
@end

@implementation LumiChatAppearanceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Цвета чата";
    self.view.backgroundColor = LumiBackgroundColor();
    self.keys = [LumiChatAppearance allKeys];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = LumiBackgroundColor();
    self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Сброс"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(resetTapped)];
    [self buildPreviewHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appearanceChanged)
                                                 name:LumiChatAppearanceDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildPreviewHeader {
    CGFloat width = MAX(280.0, CGRectGetWidth([UIScreen mainScreen].bounds));
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 168.0)];

    UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 10.0, width - 36.0, 18.0)];
    caption.text = @"ПРЕДПРОСМОТР";
    caption.textColor = LumiMutedColor();
    caption.font = LumiFont(11.0, UIFontWeightSemibold);
    [header addSubview:caption];

    UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(18.0, 36.0, width - 36.0, 118.0)];
    bubble.layer.cornerRadius = 16.0;
    bubble.tag = 101;
    [header addSubview:bubble];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12.0, 10.0, width - 60.0, 98.0)];
    label.numberOfLines = 0;
    label.tag = 102;
    [bubble addSubview:label];

    self.previewHeader = header;
    self.previewLabel = label;
    self.tableView.tableHeaderView = header;
    [self refreshPreview];
}

- (void)refreshPreview {
    LumiChatAppearance *appearance = [LumiChatAppearance sharedAppearance];
    UIView *bubble = [self.previewHeader viewWithTag:101];
    bubble.backgroundColor = appearance.characterBubbleColor;
    NSString *sample = @"**Кума** улыбается и *поправляет волосы*.\n> «Ты правда думаешь, что я не замечу?»";
    self.previewLabel.attributedText = [LumiRichTextRenderer attributedStringForText:sample
                                                                          textColor:appearance.characterTextColor
                                                                           baseFont:LumiFont(14.0, UIFontWeightRegular)
                                                                          boldColor:appearance.boldColor
                                                                        italicColor:appearance.italicColor
                                                                      quoteTextColor:appearance.quoteTextColor
                                                                      quoteFillColor:appearance.quoteFillColor
                                                                       speakerImages:nil];
}

- (void)appearanceChanged {
    [self refreshPreview];
    [self.tableView reloadData];
}

- (void)resetTapped {
    [[LumiChatAppearance sharedAppearance] resetToDefault];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Пресеты" : @"Свои цвета";
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        header.textLabel.textColor = LumiMutedColor();
        header.textLabel.font = LumiFont(12.0, UIFontWeightSemibold);
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? [LumiChatAppearance presetNames].count : self.keys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    }
    cell.backgroundColor = LumiSurfaceColor();
    cell.textLabel.textColor = LumiTextColor();
    cell.detailTextLabel.textColor = LumiMutedColor();
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    LumiChatAppearance *appearance = [LumiChatAppearance sharedAppearance];
    if (indexPath.section == 0) {
        NSArray *names = [LumiChatAppearance presetNames];
        NSString *name = names[indexPath.row];
        UIColor *dot = [LumiChatAppearance previewColorForPresetNamed:name];
        cell.textLabel.text = name;
        cell.imageView.image = dot ? LumiCircleImage(dot, 22.0, NO) : nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = (!appearance.isCustom && [appearance.presetName isEqualToString:name])
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.tintColor = appearance.boldColor;
    } else {
        NSString *key = self.keys[indexPath.row];
        cell.textLabel.text = [LumiChatAppearance localizedNameForKey:key];
        cell.imageView.image = LumiCircleImage([[LumiChatAppearance sharedAppearance] colorForKey:key] ?: LumiAccentColor(),
                                               22.0, YES);
        cell.detailTextLabel.text = [[LumiChatAppearance sharedAppearance] hexStringForKey:key];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LumiChatAppearance *appearance = [LumiChatAppearance sharedAppearance];
    if (indexPath.section == 0) {
        NSArray *names = [LumiChatAppearance presetNames];
        if (indexPath.row < (NSInteger)names.count) {
            [appearance applyPresetNamed:names[indexPath.row]];
        }
        return;
    }
    if (indexPath.row >= (NSInteger)self.keys.count) {
        return;
    }
    NSString *key = self.keys[indexPath.row];
    LumiColorPickerViewController *picker = [[LumiColorPickerViewController alloc] init];
    picker.title = [LumiChatAppearance localizedNameForKey:key];
    picker.elementName = [LumiChatAppearance localizedNameForKey:key];
    picker.selectedColor = [appearance colorForKey:key];
    __weak typeof(appearance) weakAppearance = appearance;
    picker.selectionHandler = ^(UIColor *color) {
        [weakAppearance setHexString:[LumiChatAppearance hexStringFromColor:color] forKey:key];
    };
    // Push instead of presenting modally: the picker is a normal navigation
    // step, so the standard back button returns to the palette list. The old
    // modal flow had no way to dismiss on iOS 12 and looked "broken".
    if (self.navigationController) {
        [self.navigationController pushViewController:picker animated:YES];
        return;
    }
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = appearance.boldColor ?: LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPreview];
    [self.tableView reloadData];
}

@end
