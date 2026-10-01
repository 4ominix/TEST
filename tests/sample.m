#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <assert.h>
#include <stdio.h>
#import "ICSample.h"
int main(void){@autoreleasepool{
    CVPixelBufferRef real=NULL,pixels=NULL,wrongSize=NULL;
    assert(CVPixelBufferCreate(kCFAllocatorDefault,64,64,kCVPixelFormatType_32BGRA,NULL,&real)==kCVReturnSuccess);
    assert(CVPixelBufferCreate(kCFAllocatorDefault,64,64,kCVPixelFormatType_32BGRA,NULL,&pixels)==kCVReturnSuccess);
    assert(CVPixelBufferCreate(kCFAllocatorDefault,128,64,kCVPixelFormatType_32BGRA,NULL,&wrongSize)==kCVReturnSuccess);
    CVBufferSetAttachment(real,kCVImageBufferColorPrimariesKey,kCVImageBufferColorPrimaries_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);
    CMVideoFormatDescriptionRef format=NULL;
    assert(CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,real,&format)==noErr);
    assert(CMVideoFormatDescriptionMatchesImageBuffer(format,real));
    // Same fourcc and dimensions, different attachment metadata.
    assert(!CMVideoFormatDescriptionMatchesImageBuffer(format,pixels));
    CMSampleTimingInfo timing={CMTimeMake(1,30),CMTimeMake(123,30),kCMTimeInvalid};
    CMSampleBufferRef original=NULL,bad=NULL;
    assert(CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,real,YES,NULL,NULL,format,&timing,&original)==noErr);
    OSStatus code=CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,pixels,YES,NULL,NULL,format,&timing,&bad);
    assert(code!=noErr);if(bad)CFRelease(bad);
    CMSetAttachment(original,CFSTR("iCamV3.test"),CFSTR("preserved"),kCMAttachmentMode_ShouldPropagate);
    CFArrayRef source=CMSampleBufferGetSampleAttachmentsArray(original,YES);
    CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(source,0),kCMSampleAttachmentKey_NotSync,kCFBooleanTrue);
    CMSampleBufferRef result=ICCopySampleFromPixels(original,pixels,&code);
    assert(result && code==noErr && CMSampleBufferGetImageBuffer(result)==pixels);
    assert(CMVideoFormatDescriptionMatchesImageBuffer(CMSampleBufferGetFormatDescription(result),pixels));
    assert(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(result),timing.presentationTimeStamp)==0);
    assert(CMTimeCompare(CMSampleBufferGetDuration(result),timing.duration)==0);
    assert(CFEqual(CMGetAttachment(result,CFSTR("iCamV3.test"),NULL),CFSTR("preserved")));
    CFArrayRef destination=CMSampleBufferGetSampleAttachmentsArray(result,NO);
    assert(CFDictionaryGetValue((CFDictionaryRef)CFArrayGetValueAtIndex(destination,0),kCMSampleAttachmentKey_NotSync)==kCFBooleanTrue);
    assert(CMSampleBufferGetImageBuffer(original)==real);
    assert(!ICCopySampleFromPixels(original,wrongSize,&code) && code!=noErr);
    assert(!ICCopySampleFromPixels(NULL,pixels,&code) && code!=noErr);
    assert(!ICCopySampleFromPixels(original,NULL,&code) && code!=noErr);
    CFRelease(result);CFRelease(original);CFRelease(format);CVPixelBufferRelease(real);CVPixelBufferRelease(pixels);CVPixelBufferRelease(wrongSize);
    puts("PASS: native sample format compatibility, original immutability, timing, attachments and failure paths");return 0;
}}
