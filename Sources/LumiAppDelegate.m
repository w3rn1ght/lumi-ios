#import "LumiAppDelegate.h"
#import "LumiWebViewController.h"

@implementation LumiAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor colorWithRed:0.043
                                                  green:0.043
                                                   blue:0.071
                                                  alpha:1.0];
    self.window.rootViewController = [[LumiWebViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
