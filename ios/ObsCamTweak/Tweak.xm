// ObsCamTweak — OBS/MediaMTX HLS -> camera feed
// Hook: AVCaptureVideoDataOutput sample buffer delegate
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

static NSString *const kPrefDomain = @"com.camkey.obscamtweak";
static NSString *const kPrefKey = @"streamURL";
static NSString *const kFallbackURL = @"http://192.168.1.10:8888/live/test/index.m3u8";

static NSString *CKStreamURL(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)kPrefKey,
                                                    (__bridge CFStringRef)kPrefDomain);
    NSString *s = v ? (__bridge_transfer NSString *)v : nil;
    if (s.length < 8) s = kFallbackURL;
    return s;
}

#pragma mark - frame source

@interface CKSource : NSObject
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItemVideoOutput *output;
@property (nonatomic, assign) CVPixelBufferRef lastBuffer;
+ (instancetype)shared;
- (void)startIfNeeded;
- (CMSampleBufferRef)copySampleBuffer CF_RETURNS_RETAINED;
@end

@implementation CKSource

+ (instancetype)shared {
    static CKSource *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [CKSource new]; });
    return s;
}

- (void)startIfNeeded {
    if (self.player) return;

    NSDictionary *attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    self.output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
    self.output.suppressesPlayerRendering = NO;

    NSURL *url = [NSURL URLWithString:CKStreamURL()];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
        @"AVURLAssetHTTPHeaderFieldsKey": @{@"User-Agent": @"ObsCam/1.0"}
    }];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.preferredForwardBufferDuration = 0.2;
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = YES;
    if ([item respondsToSelector:@selector(setPreferredPeakBitRate:)]) item.preferredPeakBitRate = 0;

    [item addOutput:self.output];

    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.automaticallyWaitsToMinimizeStalling = NO;
    self.player.muted = YES;
    [self.player play];
}

- (CMSampleBufferRef)copySampleBuffer CF_RETURNS_RETAINED {
    [self startIfNeeded];

    CMTime itemTime = [self.output itemTimeForHostTime:CACurrentMediaTime()];
    CVPixelBufferRef pb = NULL;
    if ([self.output hasNewPixelBufferForItemTime:itemTime]) {
        pb = [self.output copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
        if (pb) {
            if (self.lastBuffer) CVPixelBufferRelease(self.lastBuffer);
            self.lastBuffer = CVPixelBufferRetain(pb);
        }
    }
    if (!pb) {
        if (!self.lastBuffer) return NULL;
        pb = CVPixelBufferRetain(self.lastBuffer);
        itemTime = CMClockGetTime(CMClockGetHostTimeClock());
    }

    CMVideoFormatDescriptionRef fmt = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pb, &fmt) != noErr) {
        CVPixelBufferRelease(pb);
        return NULL;
    }
    CMSampleTimingInfo timing = { CMTimeMake(1, 30), itemTime, kCMTimeInvalid };
    CMSampleBufferRef sb = NULL;
    OSStatus st = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pb, fmt, &timing, &sb);
    CFRelease(fmt);
    CVPixelBufferRelease(pb);
    return (st == noErr) ? sb : NULL;
}

@end

#pragma mark - driver: feed the app's delegate

@interface CKDriver : NSObject
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) AVCaptureVideoDataOutput *output;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_source_t timer;
+ (instancetype)shared;
- (void)bindOutput:(AVCaptureVideoDataOutput *)output delegate:(id)delegate queue:(dispatch_queue_t)queue;
- (void)stop;
@end

@implementation CKDriver

+ (instancetype)shared {
    static CKDriver *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [CKDriver new]; });
    return s;
}

- (void)bindOutput:(AVCaptureVideoDataOutput *)output delegate:(id)delegate queue:(dispatch_queue_t)queue {
    if (!delegate) return;
    self.output = output;
    self.delegate = delegate;
    self.queue = queue ?: dispatch_get_main_queue();
    [self startTimer];
}

- (void)startTimer {
    if (self.timer) return;
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    uint64_t interval = NSEC_PER_SEC / 30;
    dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, interval), interval, interval / 2);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.timer, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.delegate) return;

        CMSampleBufferRef sb = [[CKSource shared] copySampleBuffer];
        if (!sb) return;

        id<AVCaptureVideoDataOutputSampleBufferDelegate> d = self.delegate;
        AVCaptureVideoDataOutput *out = self.output;
        if ([d respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            AVCaptureConnection *conn = nil;
            @try {
                if ([out respondsToSelector:@selector(connectionWithMediaType:)]) {
                    conn = [out connectionWithMediaType:AVMediaTypeVideo];
                }
            } @catch (__unused NSException *e) {}
            [d captureOutput:out didOutputSampleBuffer:sb fromConnection:conn];
            CFRelease(sb);
        } else {
            CFRelease(sb);
        }
    });
    dispatch_resume(self.timer);
}

- (void)stop {
    if (self.timer) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
    self.delegate = nil;
    [[CKSource shared].player pause];
}

@end

#pragma mark - hooks

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    %orig;
    if (delegate) {
        [[CKDriver shared] bindOutput:self delegate:delegate queue:queue];
    } else {
        [[CKDriver shared] stop];
    }
}

%end

%hook AVCaptureSession

- (void)startRunning {
    %orig;
    [[CKSource shared] startIfNeeded];
}

%end

%ctor {
    NSLog(@"[ObsCam] loaded · url=%@", CKStreamURL());
}
