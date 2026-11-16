#import <UIKit/UIKit.h>
#import "LumiDetailViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Chat details: character description, relationship state and a shortcut to
/// the chat colour settings. Reached from the ⓘ button in a chat.
@interface LumiChatInfoViewController : UIViewController

- (instancetype)initWithChat:(NSDictionary *)chat
                        item:(nullable NSDictionary *)item
                        kind:(LumiDetailKind)kind;

@end

NS_ASSUME_NONNULL_END
