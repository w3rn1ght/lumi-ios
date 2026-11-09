#import <UIKit/UIKit.h>

@interface LumiCharacterViewController : UIViewController
- (instancetype)initWithCharacterID:(NSString *)characterID
                               name:(NSString *)name
                             avatar:(NSString *)avatar;
@end
