// ObsCamTweak — OBS/MediaMTX HLS -> camera feed (system-wide) + toggle + key
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

static NSString *const kPrefDomain = @"com.camkey.obscamtweak";
static NSString *const kFallbackURL = @"http://192.168.1.10:8888/live/test/index.m3u8";
static NSString *const kFallbackServer = @"https://xml-buying-jvc-intro.trycloudflare.com";

static BOOL gEnabled = YES;
static BOOL gKeyValid = YES;

static NSString *CKPref(NSString *key, NSString *fallback) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kPrefDomain);
    NSString *s = v ? (__bridge_transfer NSString *)v : nil;
    return (s && s.length) ? s : fallback;
}

static void CKSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kPrefDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefDomain);
}

static NSString *CKStreamURL(void) { return CKPref(@"streamURL", kFallbackURL); }
static NSString *CKServer(void) { return CKPref(@"server", kFallbackServer); }
static NSString *CKKey(void) { return CKPref(@"key", @""); }
static NSString *CKDeviceID(void) {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"unknown";
}

static void CKCheckKey(void) {
    NSString *key = CKKey();
    if (key.length < 8) { gKeyValid = YES; return; }

    NSString *base = CKServer();
    if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/api/v1/public/check"]];
    if (!url) { gKeyValid = NO; return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    req.timeoutInterval = 10;
    NSDictionary *body = @{@"key": key, @"udid": CKDeviceID()};
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (!data) return;
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            BOOL valid = [obj[@"valid"] boolValue];
            dispatch_async(dispatch_get_main_queue(), ^{
                gKeyValid = valid;
                CKSetPref(@"keyValid", @(valid));
                if (!valid) gEnabled = NO;
            });
        }];
    [task resume];
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

    NSURL *url = [NSURL URLWithString:CKStreamURL()];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
        @"AVURLAssetHTTPHeaderFieldsKey": @{@"User-Agent": @"ObsCam/1.0"}
    }];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.preferredForwardBufferDuration = 0.2;
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = YES;
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

#pragma mark - driver

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
        if (!gEnabled || !gKeyValid) return;

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
        }
        CFRelease(sb);
    });
    dispatch_resume(self.timer);
}

- (void)stop {
    if (self.timer) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
    self.delegate = nil;
}

@end

#pragma mark - floating toggle

@interface CKToggleWindow : UIWindow
@end

@implementation CKToggleWindow

static CKToggleWindow *gToggleWindow = nil;

+ (void)install {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gToggleWindow) return;
        CGRect screen = [UIScreen mainScreen].bounds;
        gToggleWindow = [[CKToggleWindow alloc] initWithFrame:CGRectMake(screen.size.width - 74, 110, 64, 64)];
        gToggleWindow.windowLevel = UIWindowLevelAlert + 1;
        gToggleWindow.backgroundColor = [UIColor clearColor];
        gToggleWindow.rootViewController = [UIViewController new];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, 0, 64, 64);
        btn.layer.cornerRadius = 32;
        btn.layer.masksToBounds = YES;
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [btn setTitle:@"CAM" forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
        [gToggleWindow.rootViewController.view addSubview:btn];

        gToggleWindow.hidden = NO;
        [self refreshButton:btn];
    });
}

+ (void)refreshButton:(UIButton *)btn {
    BOOL on = gEnabled && gKeyValid;
    btn.backgroundColor = on ? [UIColor colorWithRed:0.1 green:0.65 blue:0.3 alpha:0.9]
                             : [UIColor colorWithRed:0.4 green:0.4 blue:0.45 alpha:0.9];
}

+ (void)toggle:(UIButton *)btn {
    if (!gKeyValid) {
        CKCheckKey();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self refreshButton:btn]; });
        return;
    }
    gEnabled = !gEnabled;
    CKSetPref(@"enabled", @(gEnabled));
    [self refreshButton:btn];
    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [h impactOccurred];
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
    [CKToggleWindow install];
}

%end

%hook UIApplication

- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    [CKToggleWindow install];
}

%end

%ctor {
    gEnabled = [CKPref(@"enabled", @"1") boolValue];
    gKeyValid = [CKPref(@"keyValid", @"1") boolValue];
    CKCheckKey();
    NSLog(@"[ObsCam] loaded · url=%@ key=%@", CKStreamURL(), CKKey().length ? @"yes" : @"no");
}
