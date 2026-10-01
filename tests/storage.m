// Native macOS Foundation checks. Test paths are compiled in only with IC_TESTING.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <assert.h>
#import <math.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import "ICSettings.h"
#import "ICPaths.h"
int main(int argc,const char **argv){@autoreleasepool{
    if(argc==2 && strcmp(argv[1],"increment")==0){
        for(int i=0;i<20;i++) {
            NSError *error=nil;assert(ICUpdateSettings(^(NSMutableDictionary *s){s[@"X"]=@([s[@"X"] doubleValue]+.01);},&error));assert(!error);
        }
        return 0;
    }
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    setenv("IC_TEST_STORAGE",base.UTF8String,1);
    NSDictionary *normalized=ICNormalize(@{@"Enabled":@YES,@"Media":@"../bad",@"Zoom":@100,@"X":@NAN,@"Y":@100,@"Rotation":@(-90),@"Unused":@1});
    assert(![normalized[@"Enabled"] boolValue] && [normalized[@"Media"] length]==0);
    assert([normalized[@"Zoom"] doubleValue]==8 && [normalized[@"X"] doubleValue]==0 && [normalized[@"Y"] doubleValue]==2);
    assert([normalized[@"Rotation"] intValue]==270 && !normalized[@"Unused"]);
    NSError *error=nil;assert(ICUpdateSettings(^(NSMutableDictionary *s){[s setDictionary:ICDefaults()];},&error));assert(!error);
    assert(!ICUpdateSettings(^(NSMutableDictionary *s){s[@"Enabled"]=@YES;},&error));assert(error);
    error=nil;NSString *name=@"source-fixture.bin";NSString *path=ICManagedMediaPath(name,&error);assert(path && !error);
    assert([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
    assert(ICUpdateSettings(^(NSMutableDictionary *s){s[@"Media"]=name;s[@"Enabled"]=@YES;},&error));
    NSMutableArray<NSTask *> *children=[NSMutableArray new];
    for(int i=0;i<2;i++) {
        NSTask *child=[NSTask new];child.executableURL=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];child.arguments=@[@"increment"];
        NSMutableDictionary *environment=[NSProcessInfo.processInfo.environment mutableCopy];environment[@"IC_TEST_STORAGE"]=base;child.environment=environment;
        assert([child launchAndReturnError:&error]);[children addObject:child];
    }
    for(NSTask *child in children){[child waitUntilExit];assert(child.terminationStatus==0);}
    NSDictionary *settings=ICReadSettings(&error);assert(!error);assert(fabs([settings[@"X"] doubleValue]-.4)<1e-8);
    assert([settings[@"Enabled"] boolValue] && [settings[@"Media"] isEqual:name]);
    NSString *file=[base stringByAppendingPathComponent:@"Settings.plist"];
    assert([[@"broken plist" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:file atomically:YES]);
    error=nil;settings=ICReadSettings(&error);assert(error && ![settings[@"Enabled"] boolValue]);
    error=nil;assert(ICUpdateSettings(^(NSMutableDictionary *s){[s setDictionary:ICDefaults()];},&error));
    settings=ICReadSettings(&error);assert(!error && ![settings[@"Enabled"] boolValue]);
    assert([NSFileManager.defaultManager removeItemAtPath:base error:&error]);
    puts("PASS: native settings normalization, corrupt-config recovery and 40 cross-process atomic updates");
    return 0;
}}
