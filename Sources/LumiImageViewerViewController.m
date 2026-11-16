#import "LumiImageViewerViewController.h"
#import "LumiImageLoader.h"
#import "LumiTheme.h"

@interface LumiImageViewerViewController () <UIScrollViewDelegate>

@property (nonatomic, copy, nullable) NSString *imageURLString;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, copy, nullable) NSString *imageTitle;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *hintLabel;

@end

@implementation LumiImageViewerViewController

- (instancetype)initWithImageURL:(NSString *)urlString title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _imageURLString = [urlString copy];
        _imageTitle = [title copy];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (instancetype)initWithImage:(UIImage *)image title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _image = image;
        _imageTitle = [title copy];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
    [self.scrollView addSubview:self.imageView];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"✕" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    closeButton.layer.cornerRadius = 20.0;
    [closeButton addTarget:self action:@selector(dismissSelf) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = self.imageTitle;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = LumiFont(16.0, UIFontWeightSemibold);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    [self.view addSubview:self.titleLabel];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.text = @"Сведите пальцы для масштаба · нажмите, чтобы закрыть";
    self.hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    self.hintLabel.font = LumiFont(11.0, UIFontWeightRegular);
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.hintLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12.0],
        [closeButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [closeButton.widthAnchor constraintEqualToConstant:40.0],
        [closeButton.heightAnchor constraintEqualToConstant:40.0],

        [self.titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:closeButton.trailingAnchor constant:8.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24.0],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissSelf)];
    singleTap.numberOfTapsRequired = 1;
    [self.scrollView addGestureRecognizer:singleTap];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:doubleTap];
    [singleTap requireGestureRecognizerToFail:doubleTap];

    if (self.image) {
        self.imageView.image = self.image;
    } else if (self.imageURLString.length) {
        [self.spinner startAnimating];
        __weak typeof(self) weakSelf = self;
        [[LumiImageLoader sharedLoader] loadURLString:self.imageURLString completion:^(UIImage *image) {
            if (!image) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                LumiImageViewerViewController *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                [strongSelf.spinner stopAnimating];
                strongSelf.imageView.image = image;
            });
        }];
    }
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (self.scrollView.zoomScale > 1.0) {
        [self.scrollView setZoomScale:1.0 animated:YES];
        return;
    }
    CGPoint point = [gesture locationInView:self.imageView];
    CGFloat scale = 2.5;
    CGFloat width = CGRectGetWidth(self.scrollView.bounds) / scale;
    CGFloat height = CGRectGetHeight(self.scrollView.bounds) / scale;
    CGRect zoomRect = CGRectMake(point.x - width / 2.0, point.y - height / 2.0, width, height);
    [self.scrollView zoomToRect:zoomRect animated:YES];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

@end
