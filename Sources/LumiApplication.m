#import "LumiApplication.h"

NSString *const LumiApplicationDidShakeNotification = @"LumiApplicationDidShakeNotification";

@implementation LumiApplication

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        [[NSNotificationCenter defaultCenter] postNotificationName:LumiApplicationDidShakeNotification
                                                            object:self];
        return;
    }
    [super motionEnded:motion withEvent:event];
}

@end
