#import <UIKit/UIKit.h>

@interface LumiAuthViewController : UIViewController
@property (nonatomic, copy, nullable) void (^onSuccess)(void);
@end
