#import "ICPaths.h"
#import <dlfcn.h>
#import <stdlib.h>

NSError *ICError(NSString *message) {
    return [NSError errorWithDomain:@"iCamV3.Rebuild" code:1
                          userInfo:@{NSLocalizedDescriptionKey:message ?: @"Lỗi không xác định"}];
}
NSString *ICStorageDirectory(NSError **error) {
#ifdef IC_TESTING
    const char *test = getenv("IC_TEST_STORAGE");
    if (test && test[0]=='/') return [NSString stringWithUTF8String:test];
#endif
    // No hard link to libroothide: a missing bootstrap must not prevent app startup.
    typedef const char *(*Resolver)(const char *);
    Resolver resolver = (Resolver)dlsym(RTLD_DEFAULT, "jbroot");
    if (resolver) {
        const char *path = resolver("/var/mobile/Library/iCamV3Rebuild");
        if (path && path[0]=='/') {
            NSString *resolved=[NSString stringWithUTF8String:path];
            if(resolved && ![resolved isEqualToString:@"/var/mobile/Library/iCamV3Rebuild"])return resolved;
        }
    }
    Dl_info image = {0};
    if (dladdr((const void *)&ICStorageDirectory, &image) && image.dli_fname) {
        NSString *folder = [[NSString stringWithUTF8String:image.dli_fname] stringByDeletingLastPathComponent];
        NSString *link = [folder stringByAppendingPathComponent:@".jbroot"];
        NSString *root = link.stringByResolvingSymlinksInPath;
        BOOL directory = NO;
        if (![root isEqualToString:link] && [[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&directory] && directory)
            return [root stringByAppendingPathComponent:@"var/mobile/Library/iCamV3Rebuild"];
    }
    if (error) *error = ICError(@"Không tìm thấy RootHide .jbroot. Cài gói bằng Sileo trong bootstrap đang hoạt động, rồi làm mới biểu tượng app.");
    return nil; // Never fall back to writing the real system /var/mobile/Library.
}
NSString *ICManagedMediaPath(NSString *name, NSError **error) {
    if (![name isKindOfClass:NSString.class] || ![name hasPrefix:@"source-"] ||
        ![name isEqualToString:name.lastPathComponent] || [name containsString:@"/"] || [name containsString:@"\\"] ||
        name.length>128) {
        if (error) *error=ICError(@"Tên tệp media không hợp lệ."); return nil;
    }
    NSString *base=ICStorageDirectory(error);
    return base ? [base stringByAppendingPathComponent:name] : nil;
}
