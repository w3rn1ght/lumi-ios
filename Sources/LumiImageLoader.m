#import "LumiImageLoader.h"
#import "LumiWebP.h"
#import "LumiSafe.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static const void *kLumiImageLoaderURLKey = &kLumiImageLoaderURLKey;
static const void *kLumiImageLoaderStateKey = &kLumiImageLoaderStateKey;

typedef NS_ENUM(NSInteger, LumiImageLoadState) {
    LumiImageLoadStateLoading = 0,
    LumiImageLoadStateLoaded = 1,
    LumiImageLoadStateFailed = 2,
};

static void LumiSetImageLoadState(UIImageView *view, NSString *url, LumiImageLoadState state) {
    if (!view) {
        return;
    }
    NSDictionary *previous = objc_getAssociatedObject(view, kLumiImageLoaderStateKey);
    if (![previous isKindOfClass:[NSDictionary class]]) {
        previous = nil;
    }
    NSString *previousURL = objc_getAssociatedObject(view, kLumiImageLoaderURLKey);
    NSInteger previousAttempts = [previousURL isEqualToString:url] ? [previous[@"attempts"] integerValue] : 0;
    NSInteger attempts = 0;
    if (state == LumiImageLoadStateFailed) {
        // Count retries per view+URL so a dead URL is not hammered forever.
        attempts = previousAttempts + 1;
    } else if (state == LumiImageLoadStateLoading) {
        // Keep the counter across retries: otherwise every retry looks like the
        // first failure and the backoff never grows.
        attempts = previousAttempts;
    }
    objc_setAssociatedObject(view, kLumiImageLoaderURLKey, [url copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(view, kLumiImageLoaderStateKey,
                             @{@"state": @(state), @"date": [NSDate date], @"attempts": @(attempts)},
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSDictionary *LumiImageLoadStateInfo(UIImageView *view) {
    id state = objc_getAssociatedObject(view, kLumiImageLoaderStateKey);
    return [state isKindOfClass:[NSDictionary class]] ? (NSDictionary *)state : nil;
}
static const NSUInteger kLumiImageCacheLimit = 140;
static const NSUInteger kLumiImageDiskLimit = 700;
static const CGFloat kLumiImageMaxDimension = 640.0;
static const CGFloat kLumiAnimatedFrameMaxDimension = 360.0;
static const NSUInteger kLumiAnimatedFrameLimit = 40;

@interface LumiImageLoader ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, copy) NSString *diskDirectory;
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
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 30.0;
        configuration.HTTPMaximumConnectionsPerHost = 6;
        configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        _session = [NSURLSession sessionWithConfiguration:configuration];
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = kLumiImageCacheLimit;
        // A hard byte budget: 700 px portraits used to eat hundreds of
        // megabytes and the system killed the app (looks like a crash).
        _memoryCache.totalCostLimit = 96 * 1024 * 1024;
        _workQueue = dispatch_queue_create("com.w3rn1ght.lumi.images", DISPATCH_QUEUE_CONCURRENT);

        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        _diskDirectory = [caches stringByAppendingPathComponent:@"LumiImages"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_diskDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    }
    return self;
}

#pragma mark - Public

- (UIImage *)cachedImageForURLString:(NSString *)urlString {
    if (!LumiAsString(urlString).length) {
        return nil;
    }
    return [self.memoryCache objectForKey:urlString];
}

- (void)loadURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView {
    urlString = LumiAsString(urlString);
    if (!urlString.length || !imageView) {
        return;
    }
    UIImage *cached = [self.memoryCache objectForKey:urlString];
    if (cached) {
        LumiSetImageLoadState(imageView, urlString, LumiImageLoadStateLoaded);
        imageView.image = cached;
        return;
    }

    NSString *currentURL = objc_getAssociatedObject(imageView, kLumiImageLoaderURLKey);
    if ([currentURL isEqualToString:urlString]) {
        // Cells are reconfigured on every stream flush; re-requesting the same
        // avatar used to reset the image to the placeholder and flicker.
        NSDictionary *state = LumiImageLoadStateInfo(imageView);
        LumiImageLoadState status = (LumiImageLoadState)[state[@"state"] integerValue];
        NSDate *date = state[@"date"];
        BOOL failedRecently = status == LumiImageLoadStateFailed
            && [date isKindOfClass:[NSDate class]]
            && -[date timeIntervalSinceNow] < 8.0;
        // Loading or loaded: nothing to do. Failed long ago (e.g. the first
        // burst of requests timed out at launch) is retried, otherwise the
        // avatar stays a placeholder until the app is restarted.
        if (status == LumiImageLoadStateLoading || status == LumiImageLoadStateLoaded || failedRecently) {
            return;
        }
    }
    imageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    [self loadURLString:urlString intoImageView:imageView placeholder:YES];
}

- (void)loadURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView placeholder:(BOOL)usePlaceholder {
    urlString = LumiAsString(urlString);
    if (!urlString.length || !imageView) {
        return;
    }
    LumiSetImageLoadState(imageView, urlString, LumiImageLoadStateLoading);

    UIImage *cached = [self.memoryCache objectForKey:urlString];
    if (cached) {
        LumiSetImageLoadState(imageView, urlString, LumiImageLoadStateLoaded);
        imageView.image = cached;
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakImageView = imageView;
    [self loadURLString:urlString completion:^(UIImage *image) {
        UIImageView *strongImageView = weakImageView;
        if (!strongImageView) {
            return;
        }
        NSString *currentURL = objc_getAssociatedObject(strongImageView, kLumiImageLoaderURLKey);
        if (currentURL.length && ![currentURL isEqualToString:urlString]) {
            return;
        }
        if (!image) {
            LumiSetImageLoadState(strongImageView, urlString, LumiImageLoadStateFailed);
            NSDictionary *state = LumiImageLoadStateInfo(strongImageView);
            NSInteger attempts = [state[@"attempts"] integerValue];
            NSLog(@"[Lumi] image failed (%ld): %@", (long)attempts, urlString);
            if (attempts <= 3) {
                // A short-lived network hiccup at launch used to leave the
                // portrait as a placeholder until the app was restarted.
                [self scheduleRetryForImageView:strongImageView
                                      urlString:urlString
                                          delay:2.0 * (NSTimeInterval)attempts];
            }
            return;
        }
        LumiSetImageLoadState(strongImageView, urlString, LumiImageLoadStateLoaded);
        strongImageView.image = image;
        [strongImageView setNeedsLayout];
    }];
    (void)weakSelf;

    // Watchdog: a request that never calls back must not pin this view in the
    // `Loading` state, otherwise every later configure silently gives up.
    __weak UIImageView *watchView = imageView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIImageView *view = watchView;
        if (!view) {
            return;
        }
        NSString *current = objc_getAssociatedObject(view, kLumiImageLoaderURLKey);
        if (![current isEqualToString:urlString]) {
            return;
        }
        NSDictionary *state = LumiImageLoadStateInfo(view);
        if ((LumiImageLoadState)[state[@"state"] integerValue] != LumiImageLoadStateLoading) {
            return;
        }
        LumiSetImageLoadState(view, urlString, LumiImageLoadStateFailed);
        [self loadURLString:urlString intoImageView:view placeholder:YES];
    });
}

/// Retries a failed load while the view still shows the same URL, backing off
/// so a genuinely dead URL does not spin.
- (void)scheduleRetryForImageView:(UIImageView *)imageView
                        urlString:(NSString *)urlString
                            delay:(NSTimeInterval)delay {
    __weak UIImageView *weakView = imageView;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIImageView *view = weakView;
        LumiImageLoader *loader = weakSelf;
        if (!view || !loader) {
            return;
        }
        NSString *current = objc_getAssociatedObject(view, kLumiImageLoaderURLKey);
        if (![current isEqualToString:urlString]) {
            return;
        }
        NSDictionary *state = LumiImageLoadStateInfo(view);
        if ((LumiImageLoadState)[state[@"state"] integerValue] != LumiImageLoadStateFailed) {
            return;
        }
        [loader loadURLString:urlString intoImageView:view placeholder:YES];
    });
}

- (void)loadURLString:(NSString *)urlString completion:(void (^)(UIImage *))completion {
    if (!completion) {
        return;
    }
    urlString = LumiAsString(urlString);
    if (!urlString.length) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }
    UIImage *cached = [self.memoryCache objectForKey:urlString];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cached);
        });
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }

    NSString *diskPath = [self.diskDirectory stringByAppendingPathComponent:[self cacheFileNameForURLString:urlString]];
    NSData *localData = [NSData dataWithContentsOfFile:diskPath];
    if (localData.length) {
        __weak typeof(self) weakSelf = self;
        [self decodeData:localData urlString:urlString completion:^(UIImage *image) {
            if (image) {
                completion(image);
                return;
            }
            // A truncated or HTML error response written by an older build used
            // to poison the disk cache: every later load decoded nothing and the
            // portrait stayed a placeholder until the app was reinstalled.
            [[NSFileManager defaultManager] removeItemAtPath:diskPath error:NULL];
            [weakSelf fetchAndDecodeURL:url diskPath:diskPath urlString:urlString completion:completion];
        }];
        return;
    }

    [self fetchAndDecodeURL:url diskPath:diskPath urlString:urlString completion:completion];
}

- (void)fetchAndDecodeURL:(NSURL *)url
                 diskPath:(NSString *)diskPath
                urlString:(NSString *)urlString
               completion:(void (^)(UIImage *))completion {
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? ((NSHTTPURLResponse *)response).statusCode
            : 200;
        if (error || !data.length || status >= 400) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }
        [self decodeData:data urlString:urlString completion:^(UIImage *image) {
            // Store only bytes that actually decoded: the cache must never
            // contain data the loader itself rejects.
            if (image) {
                [data writeToFile:diskPath atomically:YES];
                [weakSelf pruneDiskCacheIfNeeded];
            }
            completion(image);
        }];
    }];
    [task resume];
}

#pragma mark - Decoding

- (void)decodeData:(NSData *)data urlString:(NSString *)urlString completion:(void (^)(UIImage *))completion {
    // WebP frames are decoded at full resolution before downscaling, so a burst
    // of portraits/photos could allocate hundreds of megabytes at once. Cap how
    // many decodes run simultaneously.
    static dispatch_semaphore_t decodeLimit;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        decodeLimit = dispatch_semaphore_create(2);
    });
    dispatch_async(self.workQueue, ^{
        // Never wait forever: two stuck decodes used to freeze every portrait
        // in the app with no error and no way to recover.
        BOOL acquired = dispatch_semaphore_wait(decodeLimit,
                                                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC))) == 0;
        UIImage *image = nil;
        if (LumiDataIsWebP(data)) {
            image = LumiDecodeWebPData(data);
        }
        if (!image) {
            image = [self imageFromAnimatedData:data];
        }
        if (!image) {
            image = [UIImage imageWithData:data];
        }
        if (image && image.size.width > kLumiImageMaxDimension && image.images.count == 0) {
            image = [self downscaledImage:image maxDimension:kLumiImageMaxDimension];
        }
        if (image) {
            NSUInteger frames = MAX((NSUInteger)1, image.images.count);
            // An animated image keeps every frame alive, so charge the cache for
            // all of them; otherwise 40-frame stickers looked like 1 frame and
            // the app got jetsam-killed during long chats.
            NSUInteger cost = (NSUInteger)(image.size.width * image.size.height * 4.0) * frames;
            [self.memoryCache setObject:image forKey:urlString cost:cost];
        }
        if (acquired) {
            dispatch_semaphore_signal(decodeLimit);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image);
        });
    });
}

- (UIImage *)downscaledImage:(UIImage *)image maxDimension:(CGFloat)maxDimension {
    CGSize size = image.size;
    CGFloat scale = maxDimension / MAX(size.width, size.height);
    CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
    UIGraphicsBeginImageContextWithOptions(target, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled ?: image;
}


#pragma mark - Animated images

- (UIImage *)imageFromAnimatedData:(NSData *)data {
    if (data.length < 10) {
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    if (!source) {
        return nil;
    }
    size_t count = CGImageSourceGetCount(source);
    UIImage *result = nil;
    if (count > 1) {
        size_t frameLimit = MIN(count, kLumiAnimatedFrameLimit);
        NSMutableArray *frames = [NSMutableArray arrayWithCapacity:frameLimit];
        double totalDuration = 0.0;
        NSDictionary *thumbnailOptions = @{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(kLumiAnimatedFrameMaxDimension),
        };
        for (size_t index = 0; index < frameLimit; index++) {
            CGImageRef frameRef = CGImageSourceCreateThumbnailAtIndex(source, index,
                                                                      (__bridge CFDictionaryRef)thumbnailOptions);
            if (!frameRef) {
                frameRef = CGImageSourceCreateImageAtIndex(source, index, NULL);
            }
            if (!frameRef) {
                continue;
            }
            [frames addObject:[UIImage imageWithCGImage:frameRef]];
            CGImageRelease(frameRef);
            totalDuration += [self frameDurationAtIndex:(NSUInteger)index source:source];
        }
        if (frames.count > 1) {
            if (totalDuration <= 0.0) {
                totalDuration = 0.1 * frames.count;
            }
            result = [UIImage animatedImageWithImages:frames duration:totalDuration];
        }
    }
    if (!result) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        if (imageRef) {
            result = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
        }
    }
    CFRelease(source);
    return result;
}

- (double)frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source {
    double duration = 0.1;
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    if (!properties) {
        return duration;
    }
    CFDictionaryRef gif = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
    if (gif) {
        CFNumberRef number = CFDictionaryGetValue(gif, kCGImagePropertyGIFUnclampedDelayTime);
        if (!number) {
            number = CFDictionaryGetValue(gif, kCGImagePropertyGIFDelayTime);
        }
        if (number) {
            CFNumberGetValue(number, kCFNumberDoubleType, &duration);
        }
    }
    CFRelease(properties);
    if (duration < 0.011) {
        duration = 0.1;
    }
    return duration;
}

#pragma mark - Disk cache

- (NSString *)cacheFileNameForURLString:(NSString *)urlString {
    const char *bytes = urlString.UTF8String;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(bytes, (CC_LONG)strlen(bytes), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int index = 0; index < CC_MD5_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

- (void)pruneDiskCacheIfNeeded {
    dispatch_async(self.workQueue, ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSArray *files = [manager contentsOfDirectoryAtPath:self.diskDirectory error:NULL];
        if (files.count <= kLumiImageDiskLimit) {
            return;
        }
        NSArray *sorted = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
            NSDictionary *leftAttributes = [manager attributesOfItemAtPath:[self.diskDirectory stringByAppendingPathComponent:left] error:NULL];
            NSDictionary *rightAttributes = [manager attributesOfItemAtPath:[self.diskDirectory stringByAppendingPathComponent:right] error:NULL];
            NSDate *leftDate = leftAttributes[NSFileModificationDate] ?: [NSDate distantPast];
            NSDate *rightDate = rightAttributes[NSFileModificationDate] ?: [NSDate distantPast];
            return [leftDate compare:rightDate];
        }];
        NSUInteger removeCount = sorted.count - kLumiImageDiskLimit + 100;
        for (NSUInteger index = 0; index < removeCount && index < sorted.count; index++) {
            [manager removeItemAtPath:[self.diskDirectory stringByAppendingPathComponent:sorted[index]] error:NULL];
        }
    });
}

@end
