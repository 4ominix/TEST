#import "ICAppDelegate.h"
#import "ICMainController.h"
@implementation ICAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSLog(@"iCamV3 Rebuild: UIKit launch, build 200");
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    @try {self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[ICMainController new]];}
    @catch(NSException *exception) {
        UIViewController *fallback=[UIViewController new];fallback.view.backgroundColor=UIColor.systemBackgroundColor;
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectInset(UIScreen.mainScreen.bounds,20,80)];label.numberOfLines=0;
        label.text=[NSString stringWithFormat:@"iCamV3: lỗi giao diện\n%@\n%@\nGửi crash .ips để đối chiếu.",exception.name,exception.reason];
        [fallback.view addSubview:label];self.window.rootViewController=fallback;NSLog(@"iCamV3 UI exception: %@",exception);
    }
    // No config migration, decoder, GPU context, camera hook, or network call at launch.
    [self.window makeKeyAndVisible];return YES;
}
@end
