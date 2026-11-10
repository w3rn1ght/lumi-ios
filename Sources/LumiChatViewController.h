#import <UIKit/UIKit.h>
#import "LumiDetailViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface LumiChatViewController : UIViewController

- (instancetype)initWithChat:(NSDictionary *)chat
                        item:(nullable NSDictionary *)item
                        kind:(LumiDetailKind)kind;

@end

NS_ASSUME_NONNULL_END
