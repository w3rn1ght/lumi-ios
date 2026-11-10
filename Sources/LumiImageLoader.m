#import "LumiImageLoader.h"
#import "LumiWebP.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static const void *kLumiImageLoaderURLKey = &kLumiImageLoaderURLKey;
static const NSUInteger kLumiImageCacheLimit = 320;
static const NSUInteger kLumiImageDiskLimit = 700;

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
    if (!urlString.length) {
        return nil;
    }
    return [self.memoryCache objectForKey:urlString];
}

- (void)loadURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView {
    imageView.image = [UIImage imageNamed:@"AvatarPlaceholder"];
    [self loadURLString:urlString intoImageView:imageView placeholder:YES];
}

- (void)loadURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView placeholder:(BOOL)usePlaceholder {
    if (!urlString.length) {
        return;
    }
    objc_setAssociatedObject(imageView, kLumiImageLoaderURLKey, [urlString copy], OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIImage *cached = [self.memoryCache objectForKey:urlString];
    if (cached) {
        imageView.image = cached;
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakImageView = imageView;
    [self loadURLString:urlString completion:^(UIImage *image) {
        if (!image) {
            return;
        }
        UIImageView *strongImageView = weakImageView;
        if (!strongImageView) {
            return;
        }
        NSString *currentURL = objc_getAssociatedObject(strongImageView, kLumiImageLoaderURLKey);
        if (currentURL.length && ![currentURL isEqualToString:urlString]) {
            return;
        }
        strongImageView.image = image;
        [strongImageView setNeedsLayout];
    }];
    (void)weakSelf;
}

- (void)loadURLString:(NSString *)urlString completion:(void (^)(UIImage *))completion {
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
        [self decodeData:localData urlString:urlString completion:completion];
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url
                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }
        [data writeToFile:diskPath atomically:YES];
        [self pruneDiskCacheIfNeeded];
        [self decodeData:data urlString:urlString completion:completion];
    }];
    [task resume];
}

#pragma mark - Decoding

- (void)decodeData:(NSData *)data urlString:(NSString *)urlString completion:(void (^)(UIImage *))completion {
    dispatch_async(self.workQueue, ^{
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
        if (image && image.size.width > 700.0 && image.images.count == 0) {
            image = [self downscaledImage:image maxDimension:700.0];
        }
        if (image) {
            [self.memoryCache setObject:image forKey:urlString];
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
        NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
        double totalDuration = 0.0;
        for (size_t index = 0; index < count; index++) {
            CGImageRef frameRef = CGImageSourceCreateImageAtIndex(source, index, NULL);
            if (!frameRef) {
                continue;
            }
            [frames addObject:(__bridge id)frameRef];
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
