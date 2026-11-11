#import "LumiAppDelegate.h"
#import "LumiMainViewController.h"
#import "LumiDiagnostics.h"

@implementation LumiAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [LumiDiagnostics install];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor colorWithRed:0.043
                                                  green:0.043
                                                   blue:0.071
                                                  alpha:1.0];
    [self showRootForAuthState];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)showRootForAuthState {
    self.window.rootViewController = [[LumiMainViewController alloc] init];
    [self.window makeKeyAndVisible];
}

- (void)showAuth {
    [self showRootForAuthState];
}

- (void)showMain {
    [self showRootForAuthState];
}

@end
