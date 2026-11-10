#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LumiDetailKind) {
    LumiDetailKindCharacter = 0,
    LumiDetailKindStory = 1,
};

@interface LumiDetailViewController : UIViewController

- (instancetype)initWithItem:(NSDictionary *)item kind:(LumiDetailKind)kind;

@end

NS_ASSUME_NONNULL_END
