#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDictionary *ICDefaults(void);
FOUNDATION_EXPORT NSDictionary *ICNormalize(NSDictionary *input);
FOUNDATION_EXPORT NSDictionary *ICReadSettings(NSError **error);
FOUNDATION_EXPORT BOOL ICUpdateSettings(void (^edit)(NSMutableDictionary *settings), NSError **error);
FOUNDATION_EXPORT NSString * const ICSettingsNotification;
