#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LumiLoginViewController : UIViewController

/// Called after a successful sign-in.
@property (nonatomic, copy, nullable) void (^completion)(void);

@end

NS_ASSUME_NONNULL_END
