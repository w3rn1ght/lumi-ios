#import "LumiMainViewController.h"
#import "LumiCatalogViewController.h"
#import "LumiChatsViewController.h"
#import "LumiProfileViewController.h"
#import "LumiTheme.h"

@implementation LumiMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = LumiBackgroundColor();

    LumiCatalogViewController *catalog = [[LumiCatalogViewController alloc] init];
    LumiChatsViewController *chats = [[LumiChatsViewController alloc] init];
    LumiProfileViewController *profile = [[LumiProfileViewController alloc] init];

    self.viewControllers = @[
        [self wrap:catalog title:@"Персонажи"],
        [self wrap:chats title:@"Чаты"],
        [self wrap:profile title:@"Профиль"],
    ];

    self.tabBar.translucent = NO;
    self.tabBar.barTintColor = LumiSurfaceColor();
    self.tabBar.tintColor = LumiAccentColor();
    self.tabBar.unselectedItemTintColor = LumiMutedColor();
    self.selectedIndex = 0;
}

- (UINavigationController *)wrap:(UIViewController *)controller title:(NSString *)title {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.navigationBar.translucent = NO;
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.barTintColor = LumiBackgroundColor();
    navigation.navigationBar.tintColor = LumiAccentColor();
    navigation.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName: LumiTextColor()};
    if (@available(iOS 11.0, *)) {
        navigation.navigationBar.prefersLargeTitles = NO;
    }
    controller.title = title;
    controller.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:nil selectedImage:nil];
    return navigation;
}

@end
