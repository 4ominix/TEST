#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>
#import <stdlib.h>
#import "ICFrameEngine.h"
#import "ICSample.h"

static unsigned hookCount=0;
static CMSampleBufferRef ICCopyReplacement(CMSampleBufferRef sample) {
    if(!sample || !CMSampleBufferIsValid(sample))return NULL;
    CVPixelBufferRef original=CMSampleBufferGetImageBuffer(sample);if(!original)return NULL;
    ICFrameEngine *engine=[ICFrameEngine sharedEngine];
    CVPixelBufferRef pixels=[engine copyFrameForWidth:CVPixelBufferGetWidth(original)
        height:CVPixelBufferGetHeight(original) format:CVPixelBufferGetPixelFormatType(original)];
    if(!pixels)return NULL;
    CMSampleBufferRef replacement=NULL;
    @try {replacement=ICCopySampleFromPixels(sample,pixels,NULL);}
    @finally {CVPixelBufferRelease(pixels);}
    if(replacement)[engine recordReplacement];return replacement;
}
typedef void (*Emit)(id,SEL,CMSampleBufferRef);
typedef void (*Render)(id,SEL,CMSampleBufferRef,id);
static Emit originalEmit;
static Render originalImage,originalPhoto,originalRemote,originalStill;
static void HookEmit(id self,SEL selector,CMSampleBufferRef sample) {
    CMSampleBufferRef replacement=NULL;
    @try{replacement=ICCopyReplacement(sample);}@catch(NSException *exception){NSLog(@"iCamV3 replacement exception: %@",exception.reason);}
    @try{originalEmit(self,selector,replacement?:sample);}@finally{if(replacement)CFRelease(replacement);}
}
#define IC_RENDER_HOOK(Name,Original) \
static void Name(id self,SEL selector,CMSampleBufferRef sample,id input) { \
    CMSampleBufferRef replacement=NULL; \
    @try{replacement=ICCopyReplacement(sample);}@catch(NSException *exception){NSLog(@"iCamV3 replacement exception: %@",exception.reason);} \
    @try{Original(self,selector,replacement?:sample,input);}@finally{if(replacement)CFRelease(replacement);} \
}
IC_RENDER_HOOK(HookImage,originalImage)
IC_RENDER_HOOK(HookPhoto,originalPhoto)
IC_RENDER_HOOK(HookRemote,originalRemote)
IC_RENDER_HOOK(HookStill,originalStill)
static void InstallOne(const char *name,const char *selector,unsigned arguments,IMP replacement,IMP *original) {
    if(*original)return;
    Class cls=objc_getClass(name);SEL sel=sel_registerName(selector);
    Method method=cls?class_getInstanceMethod(cls,sel):NULL;
    if(!method || method_getNumberOfArguments(method)!=arguments)return;
    char *result=method_copyReturnType(method),*sample=method_copyArgumentType(method,2);
    BOOL compatible=result && result[0]=='v' && sample && sample[0]=='^' && strstr(sample,"CMSampleBuffer");
    if(arguments==4){char *input=method_copyArgumentType(method,3);compatible=compatible && input && input[0]=='@';free(input);}
    free(result);free(sample);if(!compatible)return;
    MSHookMessageEx(cls,sel,replacement,original);
    if(*original)hookCount++;
}
static void InstallHooks(void) {
    InstallOne("BWNodeOutput","emitSampleBuffer:",3,(IMP)HookEmit,(IMP *)&originalEmit);
    InstallOne("BWImageQueueSinkNode","renderSampleBuffer:forInput:",4,(IMP)HookImage,(IMP *)&originalImage);
    InstallOne("BWPhotoEncoderNode","renderSampleBuffer:forInput:",4,(IMP)HookPhoto,(IMP *)&originalPhoto);
    InstallOne("BWRemoteQueueSinkNode","renderSampleBuffer:forInput:",4,(IMP)HookRemote,(IMP *)&originalRemote);
    InstallOne("BWStillImageSampleBufferSinkNode","renderSampleBuffer:forInput:",4,(IMP)HookStill,(IMP *)&originalStill);
    [[ICFrameEngine sharedEngine] setInstalledHooks:hookCount];
    if(hookCount<5)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{InstallHooks();});
}
__attribute__((constructor))static void CameraInit(void) {
    dispatch_async(dispatch_get_main_queue(),^{@autoreleasepool{InstallHooks();}});
}
