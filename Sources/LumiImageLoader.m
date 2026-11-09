#import "LumiImageLoader.h"

@interface LumiImageLoader ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *cache;
@end

@implementation LumiImageLoader

+ (instancetype)sharedLoader {
    static LumiImageLoader *loader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loader = [[LumiImageLoader alloc] init];
    });
    return loader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 200;
    }
    return self;
}

- (void)loadURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView {
    imageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    if (!urlString.length) {
        return;
    }
    UIImage *cached = [self.cache objectForKey:urlString];
    if (cached) {
        imageView.image = cached;
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return;
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data.length || error) {
            return;
        }
        UIImage *image = [UIImage imageWithData:data];
        if (!image) {
            return;
        }
        [self.cache setObject:image forKey:urlString];
        dispatch_async(dispatch_get_main_queue(), ^{
            imageView.image = image;
        });
    }];
    [task resume];
}

@end
