#import "ICFrameEngine.h"
#import "ICSettings.h"
#import "ICPaths.h"
#import "ICMediaSource.h"
#import "ICRender.h"
#import "ICRequests.h"
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#import <unistd.h>
#import <string.h>

@interface ICCachedFrame : NSObject {
@public size_t width,height; OSType format; CVPixelBufferRef pixels;
}
@end
@implementation ICCachedFrame
- (void)dealloc {if(pixels)CVPixelBufferRelease(pixels);}
@end
@implementation ICFrameEngine {
    dispatch_queue_t _queue;dispatch_source_t _timer;CIContext *_context;ICMediaSource *_source;
    NSDictionary *_settings;NSString *_sourceName,*_generation,*_state;
    NSArray<ICCachedFrame *> *_frames;NSMutableArray<ICCachedFrame *> *_targets;
    os_unfair_lock _lock;ICRequest _requests[3];
    double _lastRequest,_lastPoll,_lastStatus,_healthyAt;BOOL _preview,_enabled,_dirty,_suspended;
    unsigned _hooks;unsigned long long _replaced;
}
+ (instancetype)sharedEngine {
    static ICFrameEngine *engine;static dispatch_once_t once;
    dispatch_once(&once,^{engine=[[self alloc] initForPreview:NO];});return engine;
}
- (instancetype)initForPreview:(BOOL)preview {
    if((self=[super init])) {
        _preview=preview;_lock=OS_UNFAIR_LOCK_INIT;_frames=@[];_targets=[NSMutableArray new];_state=@"idle";
        _queue=dispatch_queue_create("com.icamv3.rebuild.frames",DISPATCH_QUEUE_SERIAL);
        _timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_queue);
        dispatch_source_set_timer(_timer,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC/30,NSEC_PER_SEC/120);
        // The engine owns the timer; a strong handler capture would keep both
        // alive forever after a preview controller releases its engine.
        __weak ICFrameEngine *weakSelf=self;
        dispatch_source_set_event_handler(_timer,^{@autoreleasepool{
            ICFrameEngine *strongSelf=weakSelf;if(!strongSelf)return;
            @try {[strongSelf tick];} @catch(NSException *e){strongSelf->_state=[@"exception: " stringByAppendingString:e.reason?:@"?"];strongSelf->_source=nil;strongSelf->_sourceName=nil;[strongSelf clearFrames];}
        }});dispatch_resume(_timer);
    }return self;
}
- (void)dealloc {if(_timer)dispatch_source_cancel(_timer);}
- (void)setSuspended:(BOOL)value {
    __atomic_store_n(&_suspended,value,__ATOMIC_RELAXED);
    if(value)dispatch_async(_queue,^{
        _source=nil;_sourceName=nil;[_targets removeAllObjects];[_context clearCaches];[self clearFrames];
    });
}
- (void)setInstalledHooks:(unsigned)count {__atomic_store_n(&_hooks,count,__ATOMIC_RELAXED);}
- (void)recordReplacement {__atomic_fetch_add(&_replaced,1,__ATOMIC_RELAXED);}
- (CVPixelBufferRef)copyFrameForWidth:(size_t)width height:(size_t)height format:(OSType)format {
    if(!width||!height||width>4096||height>4096||width*height>6000000 ||
       (format!=kCVPixelFormatType_32BGRA && format!=kCVPixelFormatType_420YpCbCr8BiPlanarFullRange && format!=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange))return NULL;
    if(!os_unfair_lock_trylock(&_lock))return NULL;
    CVPixelBufferRef result=NULL;
    @try {
    _lastRequest=CACurrentMediaTime();ICRecordRequest(_requests,width,height,format,_lastRequest);
    // A stalled decoder/GPU worker must not serve stale virtual frames forever.
    if(_enabled && _lastRequest-_healthyAt<.75)for(ICCachedFrame *frame in _frames) {
        if(frame->width==width && frame->height==height && frame->format==format && frame->pixels){result=CVPixelBufferRetain(frame->pixels);break;}
    }
    } @finally {os_unfair_lock_unlock(&_lock);}return result;
}
- (void)clearFrames {
    NSArray *empty=@[];
    __attribute__((objc_precise_lifetime)) NSArray *old;
    os_unfair_lock_lock(&_lock);old=_frames;_frames=empty;_enabled=NO;_healthyAt=0;os_unfair_lock_unlock(&_lock);
    (void)old;_dirty=YES;
}
- (void)status:(double)now {
    if(now-_lastStatus<2)return;_lastStatus=now;
    NSString *base=ICStorageDirectory(NULL);if(!base)return;
    NSString *host=NSProcessInfo.processInfo.processName;
    NSString *path=[base stringByAppendingPathComponent:[NSString stringWithFormat:@"Status.%@.%d.plist",host,getpid()]];
    NSDictionary *record=@{@"Time":@(NSDate.date.timeIntervalSince1970),@"Host":host,@"PID":@(getpid()),@"State":_state?:@"?",
        @"Hooks":@(__atomic_load_n(&_hooks,__ATOMIC_RELAXED)),@"Replaced":@(__atomic_load_n(&_replaced,__ATOMIC_RELAXED))};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    [data writeToFile:path options:NSDataWritingAtomic error:NULL];
}
- (void)tick {
    double now=CACurrentMediaTime();
    if(__atomic_load_n(&_suspended,__ATOMIC_RELAXED)){_state=@"suspended";[self status:now];return;}
    ICRequest requests[3];
    os_unfair_lock_lock(&_lock);memcpy(requests,_requests,sizeof(requests));double last=_lastRequest;os_unfair_lock_unlock(&_lock);
    if(now-_lastPoll>.5) {
        _lastPoll=now;NSError *error=nil;NSDictionary *settings=ICReadSettings(&error);
        if(error){_state=error.localizedDescription;_source=nil;_sourceName=nil;_settings=settings;[self clearFrames];[self status:now];return;}
        if(![_generation isEqual:settings[@"Generation"]]){_generation=settings[@"Generation"];_dirty=YES;[self clearFrames];}
        _settings=settings;NSString *name=settings[@"Media"];
        NSString *path=name.length?ICManagedMediaPath(name,NULL):nil;
        if(!path || ![NSFileManager.defaultManager isReadableFileAtPath:path]) {
            _source=nil;_sourceName=nil;_state=@"no-readable-source";[self clearFrames];
        } else if((_preview || [settings[@"Enabled"] boolValue]) && now-last<=2 && (![_sourceName isEqual:name] || !_source)) {
            _source=[[ICMediaSource alloc] initWithPath:path kind:settings[@"Kind"] error:&error];
            _sourceName=name;_dirty=YES;[self clearFrames];_state=error.localizedDescription?:@"source-ready";
        }
    }
    if(!_source || (!_preview && ![_settings[@"Enabled"] boolValue]) || __atomic_load_n(&_suspended,__ATOMIC_RELAXED) || now-last>2) {
        _state=(!_source)?_state:@"idle-or-disabled";
        if(now-last>2 || (!_preview && ![_settings[@"Enabled"] boolValue])){_source=nil;_sourceName=nil;[_targets removeAllObjects];[_context clearCaches];}
        [self clearFrames];[self status:now];return;
    }
    os_unfair_lock_lock(&_lock);_healthyAt=now;os_unfair_lock_unlock(&_lock);
    for(NSInteger i=(NSInteger)_targets.count-1;i>=0;i--) {
        ICCachedFrame *target=_targets[(NSUInteger)i];BOOL live=NO;
        for(int j=0;j<3;j++)if(ICRequestLive(requests[j],now) && requests[j].width==target->width && requests[j].height==target->height && requests[j].format==target->format)live=YES;
        if(!live){[_targets removeObjectAtIndex:(NSUInteger)i];_dirty=YES;}
    }
    for(int i=0;i<3;i++) {
        if(!ICRequestLive(requests[i],now))continue;
        size_t width=requests[i].width,height=requests[i].height;OSType format=requests[i].format;
        BOOL found=NO;for(ICCachedFrame *target in _targets)if(target->width==width && target->height==height && target->format==format)found=YES;
        if(found)continue;
        size_t estimate=width*height*8;for(ICCachedFrame *target in _targets)estimate+=target->width*target->height*8;
        while(_targets.count && (_targets.count>=3 || estimate>48*1024*1024)) {
            ICCachedFrame *old=_targets.firstObject;estimate-=old->width*old->height*8;[_targets removeObjectAtIndex:0];
        }
        if(estimate<=48*1024*1024){ICCachedFrame *target=[ICCachedFrame new];target->width=width;target->height=height;target->format=format;[_targets addObject:target];_dirty=YES;}
    }
    if(!_source.video && !_dirty){[self status:now];return;}
    CIImage *image=[_source imageAtTime:now loop:[_settings[@"Loop"] boolValue]];
    if(!image){_state=_source.error.localizedDescription?:@"decoder-not-ready";[self clearFrames];[self status:now];return;}
    if(!_context)_context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
    if(!_context){_state=@"GPU-context-unavailable";[self clearFrames];[self status:now];return;}
    NSMutableArray *ready=[NSMutableArray new];
    for(ICCachedFrame *target in _targets) {
        CVPixelBufferRef pixels=NULL;
        NSDictionary *attributes=@{(id)kCVPixelBufferIOSurfacePropertiesKey:@{},(id)kCVPixelBufferMetalCompatibilityKey:@YES};
        if(CVPixelBufferCreate(kCFAllocatorDefault,target->width,target->height,target->format,(__bridge CFDictionaryRef)attributes,&pixels)!=kCVReturnSuccess)continue;
        CGColorSpaceRef color=NULL;
        @try {
            CIImage *composed=ICCompose(image,CGSizeMake(target->width,target->height),_settings);
            if(!composed)continue;
            color=CGColorSpaceCreateDeviceRGB();
            [_context render:composed toCVPixelBuffer:pixels bounds:composed.extent colorSpace:color];
            ICCachedFrame *frame=[ICCachedFrame new];frame->width=target->width;frame->height=target->height;frame->format=target->format;frame->pixels=pixels;pixels=NULL;[ready addObject:frame];
        } @finally {if(color)CGColorSpaceRelease(color);if(pixels)CVPixelBufferRelease(pixels);}
    }
    NSArray *next=[ready copy];__attribute__((objc_precise_lifetime)) NSArray *previous;
    os_unfair_lock_lock(&_lock);previous=_frames;_frames=next;_enabled=ready.count>0;os_unfair_lock_unlock(&_lock);(void)previous;
    _state=ready.count?@"frame-cache-ready":@"render-not-ready";_dirty=NO;[self status:now];
}
@end
