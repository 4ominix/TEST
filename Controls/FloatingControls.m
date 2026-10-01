#import <UIKit/UIKit.h>
#import <notify.h>
#import "ICSettings.h"
#import "ICAdjustments.h"
@interface ICPassWindow:UIWindow
@end
@implementation ICPassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];return (hit==self || hit==self.rootViewController.view)?nil:hit;
}
@end
@interface ICFloatingController:UIViewController
@property(nonatomic,strong) UIButton *bubble;
@property(nonatomic,strong) ICAdjustments *panel;
@property(nonatomic,strong) NSTimer *poll;
@property(nonatomic) int lockToken;
@property(nonatomic) BOOL lockAvailable;
@property(nonatomic) NSUInteger refreshGeneration;
@end
@implementation ICFloatingController
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.clearColor;
    self.bubble=[UIButton buttonWithType:UIButtonTypeSystem];self.bubble.frame=CGRectMake(MAX(8,self.view.bounds.size.width-50),self.view.bounds.size.height*.55,44,44);
    self.bubble.accessibilityLabel=@"Mở Camera control";self.bubble.backgroundColor=[UIColor colorWithWhite:.07 alpha:.94];self.bubble.layer.cornerRadius=22;
    self.bubble.tintColor=[UIColor colorWithRed:.31 green:.72 blue:.55 alpha:1];self.bubble.layer.borderWidth=1;self.bubble.layer.borderColor=[self.bubble.tintColor colorWithAlphaComponent:.6].CGColor;
    [self.bubble setImage:[UIImage systemImageNamed:@"camera.aperture"] forState:UIControlStateNormal];
    [self.bubble setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:25 weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
    [self.bubble addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];[self.view addSubview:self.bubble];
    self.panel=[ICAdjustments new];self.panel.hidden=YES;[self.view addSubview:self.panel];
    __weak typeof(self) weakSelf=self;self.panel.didClose=^{weakSelf.panel.hidden=YES;};
    self.panel.didChange=^(NSError *error){if(error)UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,error.localizedDescription);};
    self.lockToken=-1;self.lockAvailable=notify_register_dispatch("com.apple.springboard.lockstate",&_lockToken,dispatch_get_main_queue(),^(int token){[weakSelf refresh];})==NOTIFY_STATUS_OK;
    self.poll=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){[weakSelf refresh];}];[self refresh];
}
- (BOOL)isUnlocked {
    uint64_t locked=1;return self.lockAvailable && notify_get_state(self.lockToken,&locked)==NOTIFY_STATUS_OK && !locked;
}
- (void)refresh {
    NSUInteger generation=++self.refreshGeneration;
    if(![self isUnlocked]){self.bubble.hidden=YES;self.panel.hidden=YES;return;}
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *settings=ICReadSettings(NULL);
        dispatch_async(dispatch_get_main_queue(),^{
            ICFloatingController *strongSelf=weakSelf;if(!strongSelf || generation!=strongSelf.refreshGeneration)return;
            BOOL visible=[settings[@"Enabled"] boolValue] && [settings[@"Floating"] boolValue] && [strongSelf isUnlocked];
            strongSelf.bubble.hidden=!visible;if(!visible)strongSelf.panel.hidden=YES;else if(!strongSelf.panel.hidden)[strongSelf.panel refresh];
        });
    });
}
- (void)placePanel {
    CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);CGFloat margin=8;
    CGFloat width=MIN(216,MAX(0,safe.size.width*.54)),height=width*238/194;
    if(safe.size.height-2*margin<height){height=MAX(0,safe.size.height-2*margin);width=height*194/238;}
    CGFloat left=MAX(CGRectGetMinX(safe)+margin,MIN(self.bubble.center.x-width-28,CGRectGetMaxX(safe)-width-margin));
    CGFloat top=MAX(CGRectGetMinY(safe)+margin,MIN(self.bubble.center.y-height/2,CGRectGetMaxY(safe)-height-margin));
    self.panel.frame=CGRectMake(left,top,width,height);
}
- (void)toggle {
    if(self.bubble.hidden || ![self isUnlocked])return;
    [self placePanel];self.panel.hidden=!self.panel.hidden;if(!self.panel.hidden)[self.panel refresh];
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint delta=[gesture translationInView:self.view],center=self.bubble.center;CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    center.x=MIN(MAX(CGRectGetMinX(safe)+24,center.x+delta.x),CGRectGetMaxX(safe)-24);
    center.y=MIN(MAX(CGRectGetMinY(safe)+24,center.y+delta.y),CGRectGetMaxY(safe)-24);self.bubble.center=center;
    [gesture setTranslation:CGPointZero inView:self.view];self.panel.hidden=YES;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    CGPoint center=self.bubble.center;center.x=MIN(MAX(CGRectGetMinX(safe)+24,center.x),CGRectGetMaxX(safe)-24);
    center.y=MIN(MAX(CGRectGetMinY(safe)+24,center.y),CGRectGetMaxY(safe)-24);self.bubble.center=center;
    if(!self.panel.hidden)[self placePanel];
}
- (void)dealloc {if(self.lockAvailable)notify_cancel(self.lockToken);[self.poll invalidate];}
@end
static ICPassWindow *window;
static id observer;
static void ICShow(void) {
    if(window)return;window=[[ICPassWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];window.windowLevel=UIWindowLevelAlert+1;window.rootViewController=[ICFloatingController new];window.hidden=NO;
}
__attribute__((constructor))static void ControlsInit(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        observer=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){ICShow();}];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(UIApplication.sharedApplication)ICShow();});
    });
}
