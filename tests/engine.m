// Native macOS ARC/GCD test using the real engine, not a Python ownership model.
// This does not exercise UIKit, GPU media rendering or private iOS camera hooks.
#import <Foundation/Foundation.h>
#import "ICFrameEngine.h"
#import "ICPaths.h"
#import "ICSettings.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void) {@autoreleasepool {
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    setenv("IC_TEST_STORAGE",base.UTF8String,1);
    NSError *error=nil;
    assert(ICUpdateSettings(^(NSMutableDictionary *s){[s setDictionary:ICDefaults()];},&error));
    assert(!error);
    // Exercise both a running engine and its queued suspend/cleanup block.
    for(int suspend=0;suspend<2;suspend++) {
        __weak ICFrameEngine *released=nil;
        @autoreleasepool {
            ICFrameEngine *engine=[[ICFrameEngine alloc] initForPreview:YES];
            assert(engine);released=engine;
            assert(![engine copyFrameForWidth:0 height:64 format:kCVPixelFormatType_32BGRA]);
            assert(![engine copyFrameForWidth:64 height:64 format:0]);
            if(suspend)[engine setSuspended:YES];
        }
        // A handler in flight can retain the engine only until that tick returns.
        for(int i=0;i<200;i++) {
            BOOL alive;
            @autoreleasepool {alive=(released!=nil);}
            if(!alive)break;
            usleep(10000);
        }
        @autoreleasepool {assert(!released);}
    }
    // Let cancellation/worker unwinding settle before deleting this test's data.
    usleep(50000);
    assert([NSFileManager.defaultManager removeItemAtPath:base error:&error]);
    assert(!error);
    puts("PASS: native engine lifetime, running/suspended teardown and invalid request fallback");
    return 0;
}}
