#import "ICSettings.h"
#import "ICPaths.h"
#import <math.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <notify.h>

NSString * const ICSettingsNotification=@"com.icamv3.rebuild.settings";
static double ICNumber(NSDictionary *d, NSString *key, double fallback) {
    id value=d[key]; if (![value isKindOfClass:NSNumber.class]) return fallback;
    double number=[value doubleValue]; return isfinite(number)?number:fallback;
}
NSDictionary *ICDefaults(void) {
    return @{ @"Schema":@2, @"Enabled":@NO, @"Loop":@YES, @"Mirror":@NO,
              @"Floating":@NO, @"Rotation":@0, @"Fill":@NO, @"Zoom":@1,
              @"X":@0, @"Y":@0, @"Media":@"", @"Kind":@"image", @"Generation":@"" };
}
NSDictionary *ICNormalize(NSDictionary *input) {
    NSDictionary *d=[input isKindOfClass:NSDictionary.class]?input:@{};
    NSMutableDictionary *n=[ICDefaults() mutableCopy];
    for (NSString *key in @[@"Enabled",@"Loop",@"Mirror",@"Floating",@"Fill"])
        n[key]=@(ICNumber(d,key,[n[key] doubleValue])!=0);
    n[@"Zoom"]=@(fmin(8,fmax(.25,ICNumber(d,@"Zoom",1))));
    for (NSString *key in @[@"X",@"Y"]) n[key]=@(fmin(2,fmax(-2,ICNumber(d,key,0))));
    double angle=fmod(ICNumber(d,@"Rotation",0),360);
    n[@"Rotation"]=@((((int)llround(angle/90)+4)%4)*90);
    for (NSString *key in @[@"Media",@"Generation"])
        if ([d[key] isKindOfClass:NSString.class] && [d[key] length]<129) n[key]=d[key];
    if ([d[@"Kind"] isEqual:@"video"]) n[@"Kind"]=@"video";
    NSString *name=n[@"Media"];
    if (name.length && (![name hasPrefix:@"source-"] || ![name isEqualToString:name.lastPathComponent] || [name containsString:@"\\"])) {
        n[@"Media"]=@""; n[@"Enabled"]=@NO;
    }
    return n;
}
NSDictionary *ICReadSettings(NSError **error) {
    NSString *base=ICStorageDirectory(error); if (!base) return ICDefaults();
    NSString *path=[base stringByAppendingPathComponent:@"Settings.plist"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return ICDefaults();
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return ICDefaults();
    id object=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![object isKindOfClass:NSDictionary.class] || ![object[@"Schema"] isEqual:@2]) {
        if (error) *error=ICError(@"Cấu hình hỏng hoặc sai phiên bản. Camera thật được giữ nguyên; dùng Đặt lại trong app.");
        return ICDefaults();
    }
    return ICNormalize(object);
}
BOOL ICUpdateSettings(void (^edit)(NSMutableDictionary *), NSError **error) {
    NSString *base=ICStorageDirectory(error); if (!base) return NO;
    NSFileManager *fm=NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0775} error:error]) return NO;
    int fd=open([[base stringByAppendingPathComponent:@"Settings.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0664);
    if (fd<0) {if(error)*error=ICError(@"Không mở được khóa cấu hình. Kiểm tra quyền thư mục trong chẩn đoán.");return NO;}
    if (flock(fd,LOCK_EX)<0) {close(fd);if(error)*error=ICError(@"Không khóa được cấu hình.");return NO;}
    BOOL saved=NO;
    @try {
        NSMutableDictionary *n=[ICReadSettings(NULL) mutableCopy];
        edit(n); n=[ICNormalize(n) mutableCopy];n[@"Generation"]=NSUUID.UUID.UUIDString;
        NSString *media=n[@"Media"];
        if ([n[@"Enabled"] boolValue] && (!media.length || ![fm isReadableFileAtPath:ICManagedMediaPath(media,NULL)])) {
            if(error)*error=ICError(@"Hãy chọn media đọc được trước khi bật camera ảo.");
        } else {
            NSData *data=[NSPropertyListSerialization dataWithPropertyList:n format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
            NSString *path=[base stringByAppendingPathComponent:@"Settings.plist"];
            saved=data && [data writeToFile:path options:NSDataWritingAtomic error:error];
            if(saved) chmod(path.fileSystemRepresentation,0644);
        }
    } @catch(NSException *exception) {if(error)*error=ICError(exception.reason);}
    @finally {flock(fd,LOCK_UN);close(fd);}
    if(saved)notify_post(ICSettingsNotification.UTF8String);
    return saved;
}
