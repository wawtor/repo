#import "APDDisplayView.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@interface APDDisplayView ()
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation APDDisplayView {
    CMVideoFormatDescriptionRef _fmt;    // current format desc (from param sets)
    // Cached parameter sets so we can tell when they change.
    NSData *_sps, *_pps, *_vps;
    BOOL _isH265;
}

+ (Class)layerClass { return [AVSampleBufferDisplayLayer class]; }
- (AVSampleBufferDisplayLayer *)displayLayer { return (AVSampleBufferDisplayLayer *)self.layer; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        _statusLabel = [[UILabel alloc] initWithFrame:frame];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        _statusLabel.font = [UIFont systemFontOfSize:22];
        _statusLabel.numberOfLines = 0;
        _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_statusLabel];
    }
    return self;
}

- (void)layoutSubviews { [super layoutSubviews]; self.displayLayer.frame = self.bounds; _statusLabel.frame = self.bounds; }

- (void)showStatus:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = text; self.statusLabel.hidden = (text == nil); });
}

- (void)reset {
    if (_fmt) { CFRelease(_fmt); _fmt = NULL; }
    _sps = _pps = _vps = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ [self.displayLayer flushAndRemoveImage]; });
}

/* Scan an Annex-B buffer into NAL ranges (payload after the start code). */
static void scan_nals(const uint8_t *d, int len, void (^cb)(const uint8_t *nal, int nalLen)) {
    int i = 0;
    // find first start code
    int start = -1;
    while (i + 3 <= len) {
        if (d[i] == 0 && d[i+1] == 0 && d[i+2] == 1) { start = i + 3; i += 3; break; }
        if (i + 4 <= len && d[i]==0 && d[i+1]==0 && d[i+2]==0 && d[i+3]==1) { start = i + 4; i += 4; break; }
        i++;
    }
    if (start < 0) return;
    while (start < len) {
        // find next start code
        int j = start; int next = -1; int scLen = 0;
        while (j + 3 <= len) {
            if (d[j]==0 && d[j+1]==0 && d[j+2]==1) { next = j; scLen = 3; break; }
            if (j + 4 <= len && d[j]==0 && d[j+1]==0 && d[j+2]==0 && d[j+3]==1) { next = j; scLen = 4; break; }
            j++;
        }
        int nalEnd = (next < 0) ? len : next;
        if (nalEnd > start) cb(d + start, nalEnd - start);
        if (next < 0) break;
        start = next + scLen;
    }
}

- (void)rebuildFormatIfNeededH265:(BOOL)h265 {
    if (_fmt) { CFRelease(_fmt); _fmt = NULL; }
    OSStatus st;
    if (h265) {
        if (!_vps || !_sps || !_pps) return;
        const uint8_t *ps[3] = { _vps.bytes, _sps.bytes, _pps.bytes };
        size_t pl[3] = { _vps.length, _sps.length, _pps.length };
        st = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault, 3, ps, pl, 4, NULL, &_fmt);
    } else {
        if (!_sps || !_pps) return;
        const uint8_t *ps[2] = { _sps.bytes, _pps.bytes };
        size_t pl[2] = { _sps.length, _pps.length };
        st = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, ps, pl, 4, &_fmt);
    }
    if (st != noErr) { _fmt = NULL; NSLog(@"[APD] format desc failed: %d", (int)st); }
}

- (void)enqueueAnnexB:(const uint8_t *)data length:(int)length isH265:(BOOL)isH265 {
    if (length <= 0 || !data) return;
    __block BOOL paramsChanged = NO;
    // AVCC-style output for the VCL NALs (4-byte big-endian length prefix each).
    NSMutableData *avcc = [NSMutableData data];

    scan_nals(data, length, ^(const uint8_t *nal, int nalLen) {
        if (nalLen <= 0) return;
        int type;
        BOOL isParam = NO, isVCL = NO;
        if (isH265) {
            type = (nal[0] >> 1) & 0x3f;
            if (type == 32) { NSData *n=[NSData dataWithBytes:nal length:nalLen]; if(![n isEqual:_vps]){_vps=n;paramsChanged=YES;} isParam=YES; }
            else if (type == 33) { NSData *n=[NSData dataWithBytes:nal length:nalLen]; if(![n isEqual:_sps]){_sps=n;paramsChanged=YES;} isParam=YES; }
            else if (type == 34) { NSData *n=[NSData dataWithBytes:nal length:nalLen]; if(![n isEqual:_pps]){_pps=n;paramsChanged=YES;} isParam=YES; }
            else if (type <= 31) isVCL = YES;    // VCL NAL types 0..31 for HEVC
        } else {
            type = nal[0] & 0x1f;
            if (type == 7) { NSData *n=[NSData dataWithBytes:nal length:nalLen]; if(![n isEqual:_sps]){_sps=n;paramsChanged=YES;} isParam=YES; }
            else if (type == 8) { NSData *n=[NSData dataWithBytes:nal length:nalLen]; if(![n isEqual:_pps]){_pps=n;paramsChanged=YES;} isParam=YES; }
            else if (type >= 1 && type <= 5) isVCL = YES;
            // types 6 (SEI), 9 (AUD), etc. are dropped
        }
        if (isVCL) {
            uint32_t be = CFSwapInt32HostToBig((uint32_t)nalLen);
            [avcc appendBytes:&be length:4];
            [avcc appendBytes:nal length:nalLen];
        }
        (void)isParam;
    });

    if (paramsChanged || (isH265 != _isH265)) { _isH265 = isH265; [self rebuildFormatIfNeededH265:isH265]; }
    if (!_fmt || avcc.length == 0) return;

    CMBlockBufferRef bb = NULL;
    OSStatus st = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, avcc.length, kCFAllocatorDefault,
                                                     NULL, 0, avcc.length, 0, &bb);
    if (st != noErr) return;
    st = CMBlockBufferReplaceDataBytes(avcc.bytes, bb, 0, avcc.length);
    if (st != noErr) { CFRelease(bb); return; }

    CMSampleBufferRef sb = NULL;
    const size_t sz = avcc.length;
    st = CMSampleBufferCreateReady(kCFAllocatorDefault, bb, _fmt, 1, 0, NULL, 1, &sz, &sb);
    CFRelease(bb);
    if (st != noErr || !sb) return;

    // Display immediately (low-latency mirror; we don't buffer to a clock).
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sb, YES);
    if (attachments) {
        CFMutableDictionaryRef d = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(d, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    }

    AVSampleBufferDisplayLayer *layer = self.displayLayer;
    if (layer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        NSLog(@"[APD] display layer failed: %@; flushing", layer.error);
        [layer flush];
    }
    if (layer.isReadyForMoreMediaData) {
        [layer enqueueSampleBuffer:sb];
        if (!self.statusLabel.hidden) [self showStatus:nil];
    }
    CFRelease(sb);
}

- (void)dealloc { if (_fmt) CFRelease(_fmt); }
@end
