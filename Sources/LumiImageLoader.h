#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LumiImageLoader : NSObject

+ (instancetype)sharedLoader;

/// Loads a remote image (JPEG/PNG/WebP) into the image view, cancelling any previous request.
- (void)loadURLString:(nullable NSString *)urlString intoImageView:(UIImageView *)imageView;

/// Loads a remote image and hands the decoded result back on the main queue.
- (void)loadURLString:(nullable NSString *)urlString
           completion:(void (^)(UIImage * _Nullable image))completion;

/// Returns a previously decoded image from the memory cache, if any.
- (nullable UIImage *)cachedImageForURLString:(nullable NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
