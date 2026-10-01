#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
// Caller owns the result; cache/original pixel buffers are never mutated.
CMSampleBufferRef ICCopySampleFromPixels(CMSampleBufferRef original,CVPixelBufferRef pixels,OSStatus *status) CF_RETURNS_RETAINED;
