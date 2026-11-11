#import <UIKit/UIKit.h>
#import "LumiDetailViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface LumiChatViewController : UIViewController

/// 1-based position of the chat in the account's chat list; 0 when unknown.
@property (nonatomic, assign) NSUInteger chatNumber;

- (instancetype)initWithChat:(NSDictionary *)chat
                        item:(nullable NSDictionary *)item
                        kind:(LumiDetailKind)kind;

@end

NS_ASSUME_NONNULL_END
