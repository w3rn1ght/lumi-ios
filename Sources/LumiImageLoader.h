#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LumiImageLoader : NSObject

+ (instancetype)sharedLoader;
- (void)loadURLString:(nullable NSString *)urlString intoImageView:(UIImageView *)imageView;

@end

NS_ASSUME_NONNULL_END
