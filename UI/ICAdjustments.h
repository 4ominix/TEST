#import <UIKit/UIKit.h>
@interface ICAdjustments : UIView
@property(nonatomic,copy) void (^didChange)(NSError *error);
@property(nonatomic,copy) void (^didClose)(void);
- (void)refresh;
@end
