#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LumiCharacterViewController : UIViewController
- (instancetype)initWithCharacterID:(NSString *)characterID
                               name:(NSString *)name
                             avatar:(NSString *)avatar;
@end

NS_ASSUME_NONNULL_END
