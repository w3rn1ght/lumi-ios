#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Full-screen avatar viewer with pinch/double-tap zoom and a close button.
@interface LumiImageViewerViewController : UIViewController

- (instancetype)initWithImageURL:(nullable NSString *)urlString title:(nullable NSString *)title;
- (instancetype)initWithImage:(nullable UIImage *)image title:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
