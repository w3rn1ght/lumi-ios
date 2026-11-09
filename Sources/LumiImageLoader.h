#import <UIKit/UIKit.h>

@interface LumiImageLoader : NSObject

+ (instancetype)sharedLoader;
- (void)loadURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView;

@end
