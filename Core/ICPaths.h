#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSError *ICError(NSString *message);
FOUNDATION_EXPORT NSString * _Nullable ICStorageDirectory(NSError **error);
FOUNDATION_EXPORT NSString * _Nullable ICManagedMediaPath(NSString *name, NSError **error);
