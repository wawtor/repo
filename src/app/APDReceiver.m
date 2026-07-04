#import "APDReceiver.h"
#import "APDDisplayView.h"
#import <UIKit/UIKit.h>

#import "raop.h"
#import "dnssd.h"
#import "stream.h"

/* The C callbacks are global-ish; route them to the single active receiver. */
static __weak APDReceiver *gReceiver = nil;

/* Lightweight file logger — NSLog isn't visible over SSH, so mirror to a file. */
static void APDLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[APD] %@", msg);
    static NSFileHandle *fh = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = @"/var/mobile/apd.log";
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    });
    NSString *line = [NSString stringWithFormat:@"%@\n", msg];
    @try { [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; } @catch (__unused id e) {}
}

@implementation APDReceiver {
    raop_t *_raop;
    dnssd_t *_dnssd;
    unsigned short _raopPort;
    unsigned short _airplayPort;
}

#pragma mark - raop callbacks (C)

static void cb_video_process(void *cls, raop_ntp_t *ntp, video_decode_struct *data) {
    APDReceiver *self = gReceiver;
    if (!self || !data || !data->data || data->data_len <= 0) return;
    APDDisplayView *disp = self.display;
    if (!disp) return;
    // Copy out of the lib's buffer; hop to main for the display layer.
    NSData *buf = [NSData dataWithBytes:data->data length:data->data_len];
    BOOL h265 = data->is_h265;
    dispatch_async(dispatch_get_main_queue(), ^{
        [disp enqueueAnnexB:(const uint8_t *)buf.bytes length:(int)buf.length isH265:h265];
    });
}

static void cb_audio_process(void *cls, raop_ntp_t *ntp, audio_decode_struct *data) { /* audio: TODO */ }

static int cb_video_set_codec(void *cls, video_codec_t codec) {
    APDReceiver *self = gReceiver;
    NSLog(@"[APD] video_set_codec: %d", (int)codec);
    [self.display reset];
    return 0;
}

static void cb_conn_init(void *cls) {
    APDReceiver *self = gReceiver;
    NSLog(@"[APD] connection init");
    [self.display showStatus:@"Connecting…"];
}
static void cb_conn_destroy(void *cls) {
    APDReceiver *self = gReceiver;
    NSLog(@"[APD] connection destroy");
    [self.display reset];
    [self.display showStatus:@"Waiting for a Mac to connect…"];
}
static void cb_conn_reset(void *cls, int reason) {
    APDReceiver *self = gReceiver;
    NSLog(@"[APD] connection reset (%d)", reason);
    [self.display reset];
}
static void cb_conn_teardown(void *cls, bool *teardown_96, bool *teardown_110) { }
static void cb_video_reset(void *cls, reset_type_t t) { [gReceiver.display reset]; }
static void cb_video_flush(void *cls) { }
static void cb_log(void *cls, int level, const char *msg) { APDLog(@"lib: %s", msg ?: ""); }

/* --- Remaining callbacks: the handshake path invokes many of these, so they must
 *     be non-NULL even though we don't act on most of them yet. --- */
static float g_screen_w = 1920.0f, g_screen_h = 1080.0f;   // set at start from UIScreen

static void   cb_conn_feedback(void *cls) { }
static void   cb_video_pause(void *cls) { }
static void   cb_video_resume(void *cls) { }
static void   cb_audio_flush(void *cls) { }
static double cb_audio_set_client_volume(void *cls) { return 0.0; }
static void   cb_audio_set_volume(void *cls, float v) { }
static void   cb_audio_set_metadata(void *cls, const void *b, int n) { }
static void   cb_audio_set_coverart(void *cls, const void *b, int n) { }
static void   cb_audio_stop_coverart_rendering(void *cls) { }
static void   cb_audio_set_progress(void *cls, uint32_t *s, uint32_t *c, uint32_t *e) { }
static void   cb_audio_get_format(void *cls, unsigned char *ct, unsigned short *spf,
                                  bool *usingScreen, bool *isMedia, uint64_t *audioFormat) {
    if (ct) *ct = 0; if (spf) *spf = 0; if (usingScreen) *usingScreen = false;
    if (isMedia) *isMedia = false; if (audioFormat) *audioFormat = 0;
}
static void   cb_video_report_size(void *cls, float *ws, float *hs, float *w, float *h) {
    if (ws) *ws = g_screen_w; if (hs) *hs = g_screen_h;
    if (w)  *w  = g_screen_w; if (h)  *h  = g_screen_h;
}
static void   cb_mirror_video_running(void *cls, bool running) { APDLog(@"mirror_video_running: %d", running); }
static void   cb_report_client_request(void *cls, char *deviceid, char *model, char *name, bool *admit) {
    APDLog(@"client request: name=%s model=%s id=%s", name?:"", model?:"", deviceid?:"");
    if (admit) *admit = true;
}
static void   cb_display_pin(void *cls, char *pin) { }
static void   cb_register_client(void *cls, const char *device_id, const char *pk, const char *name) { }
static bool   cb_check_register(void *cls, const char *pk) { return false; }
static const char *cb_passwd(void *cls, int *len) { if (len) *len = 0; return NULL; }
static void   cb_export_dacp(void *cls, const char *ar, const char *dacp) { }
static void   cb_on_video_play(void *cls, const char *loc, const float start) { }
static void   cb_on_video_scrub(void *cls, const float pos) { }
static void   cb_on_video_rate(void *cls, const float rate) { }
static void   cb_on_video_stop(void *cls) { }
static void   cb_on_video_acquire_playback_info(void *cls, playback_info_t *info) { }
static float  cb_on_video_playlist_remove(void *cls) { return 0.0f; }

#pragma mark - lifecycle

- (BOOL)startWithError:(NSString **)err {
    gReceiver = self;

    // Record screen size for video_report_size.
    CGRect nb = [UIScreen mainScreen].nativeBounds;   // pixels, portrait
    g_screen_w = MAX(nb.size.width, nb.size.height);
    g_screen_h = MIN(nb.size.width, nb.size.height);

    raop_callbacks_t cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.cls             = (__bridge void *)self;
    cbs.audio_process   = cb_audio_process;
    cbs.video_process   = cb_video_process;
    cbs.video_set_codec = cb_video_set_codec;
    cbs.conn_init       = cb_conn_init;
    cbs.conn_destroy    = cb_conn_destroy;
    cbs.conn_reset      = cb_conn_reset;
    cbs.conn_teardown   = cb_conn_teardown;
    cbs.video_reset     = cb_video_reset;
    cbs.video_flush     = cb_video_flush;
    // Full set — the handshake calls many of these unconditionally.
    cbs.conn_feedback                 = cb_conn_feedback;
    cbs.video_pause                   = cb_video_pause;
    cbs.video_resume                  = cb_video_resume;
    cbs.audio_flush                   = cb_audio_flush;
    cbs.audio_set_client_volume       = cb_audio_set_client_volume;
    cbs.audio_set_volume              = cb_audio_set_volume;
    cbs.audio_set_metadata            = cb_audio_set_metadata;
    cbs.audio_set_coverart            = cb_audio_set_coverart;
    cbs.audio_stop_coverart_rendering = cb_audio_stop_coverart_rendering;
    cbs.audio_set_progress            = cb_audio_set_progress;
    cbs.audio_get_format              = cb_audio_get_format;
    cbs.video_report_size             = cb_video_report_size;
    cbs.mirror_video_running          = cb_mirror_video_running;
    cbs.report_client_request         = cb_report_client_request;
    cbs.display_pin                   = cb_display_pin;
    cbs.register_client               = cb_register_client;
    cbs.check_register                = cb_check_register;
    cbs.passwd                        = cb_passwd;
    cbs.export_dacp                   = cb_export_dacp;
    cbs.on_video_play                 = cb_on_video_play;
    cbs.on_video_scrub                = cb_on_video_scrub;
    cbs.on_video_rate                 = cb_on_video_rate;
    cbs.on_video_stop                 = cb_on_video_stop;
    cbs.on_video_acquire_playback_info= cb_on_video_acquire_playback_info;
    cbs.on_video_playlist_remove      = cb_on_video_playlist_remove;

    _raop = raop_init(&cbs);
    if (!_raop) { if (err) *err = @"raop_init failed"; return NO; }

    raop_set_log_callback(_raop, cb_log, NULL);
    raop_set_log_level(_raop, 2 /*LOGGER_INFO-ish*/);

    // Fixed MAC / device id (must be stable so the Mac remembers pairing).
    const char *device_id = "02:00:11:22:33:44";
    // keyfile MUST be "" not NULL — ed25519_key_generate() does strlen(keyfile) unconditionally.
    if (raop_init2(_raop, 1 /*nohold*/, device_id, "")) {
        if (err) *err = @"raop_init2 failed"; return NO;
    }

    _raopPort = 0;
    // httpd_start returns 1 on success, 0 if already running, negative on error.
    int hs = raop_start_httpd(_raop, &_raopPort);
    APDLog(@"raop_start_httpd -> %d, port=%u", hs, _raopPort);
    if (hs < 0) { if (err) *err = [NSString stringWithFormat:@"raop_start_httpd failed (%d)", hs]; return NO; }
    raop_set_port(_raop, _raopPort);
    _airplayPort = _raopPort;

    // Bonjour advertisement via native dns_sd.
    NSString *name = self.serverName.length ? self.serverName : @"iPad Display";
    const char *cname = name.UTF8String;
    // hw_addr bytes from device_id
    unsigned char hw[6] = { 0x02, 0x00, 0x11, 0x22, 0x33, 0x44 };
    int derr = 0;
    _dnssd = dnssd_init(cname, (int)strlen(cname), (const char *)hw, 6, 0, &derr);
    APDLog(@"dnssd_init -> %p err=%d", _dnssd, derr);
    if (!_dnssd || derr) { if (err) *err = [NSString stringWithFormat:@"dnssd_init failed (%d)", derr]; return NO; }

    raop_set_dnssd(_raop, _dnssd);
    int rr = dnssd_register_raop(_dnssd, _raopPort);
    APDLog(@"dnssd_register_raop(%u) -> %d", _raopPort, rr);
    if (rr) { if (err) *err = [NSString stringWithFormat:@"register_raop failed (%d)", rr]; return NO; }
    int ar = dnssd_register_airplay(_dnssd, _airplayPort);
    APDLog(@"dnssd_register_airplay(%u) -> %d", _airplayPort, ar);
    if (ar) { if (err) *err = [NSString stringWithFormat:@"register_airplay failed (%d)", ar]; return NO; }

    APDLog(@"receiver started: name=%@ raopPort=%u", name, _raopPort);
    [self.display showStatus:@"Waiting for a Mac to connect…"];
    return YES;
}

- (void)stop {
    if (_dnssd) { dnssd_unregister_raop(_dnssd); dnssd_unregister_airplay(_dnssd); }
    if (_raop)  { raop_stop_httpd(_raop); raop_destroy(_raop); _raop = NULL; }
    if (_dnssd) { dnssd_destroy(_dnssd); _dnssd = NULL; }
    gReceiver = nil;
}
@end
