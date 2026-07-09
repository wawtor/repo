#import "APDKeepAlive.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

/* Background persistence strategy: airplayd's Bonjour advert + RAOP httpd only keep
 * running while the process is scheduled. A plain UIKit app is suspended seconds after
 * it leaves the foreground, which would drop it off the AirPlay list. The one background
 * mode iOS grants a non-App-Store app without special daemon plumbing is "audio": while
 * an AVAudioSession is active and a player is playing, the app is kept running.
 *
 * So we hold a Playback session and loop a tiny silent WAV forever. mixWithOthers means
 * we never interrupt the user's music/podcasts — we're an inaudible keepalive, not audio. */

@implementation APDKeepAlive {
    AVAudioPlayer *_player;
    BOOL _running;
}

+ (instancetype)shared {
    static APDKeepAlive *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[APDKeepAlive alloc] init]; });
    return s;
}

/* Build ~1s of 8 kHz mono 16-bit PCM silence wrapped in a WAV container, in memory. */
static NSData *APDSilentWAV(void) {
    const uint32_t rate = 8000, channels = 1, bits = 16;
    const uint32_t frames = rate;                       // 1 second
    const uint32_t dataBytes = frames * channels * (bits / 8);
    const uint32_t byteRate = rate * channels * (bits / 8);
    const uint16_t blockAlign = channels * (bits / 8);
    const uint32_t riffSize = 36 + dataBytes;

    NSMutableData *d = [NSMutableData dataWithCapacity:44 + dataBytes];
    void (^u32)(uint32_t) = ^(uint32_t v){ [d appendBytes:&v length:4]; };   // little-endian on ARM
    void (^u16)(uint16_t) = ^(uint16_t v){ [d appendBytes:&v length:2]; };
    [d appendBytes:"RIFF" length:4]; u32(riffSize);
    [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4]; u32(16); u16(1 /*PCM*/); u16(channels);
    u32(rate); u32(byteRate); u16(blockAlign); u16(bits);
    [d appendBytes:"data" length:4]; u32(dataBytes);
    [d increaseLengthBy:dataBytes];                     // zero-filled => silence
    return d;
}

- (void)start {
    if (_running) return;

    AVAudioSession *sess = [AVAudioSession sharedInstance];
    NSError *e = nil;
    [sess setCategory:AVAudioSessionCategoryPlayback
          withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&e];
    if (e) NSLog(@"[APD] keepalive setCategory: %@", e);
    [sess setActive:YES error:&e];
    if (e) NSLog(@"[APD] keepalive setActive: %@", e);

    _player = [[AVAudioPlayer alloc] initWithData:APDSilentWAV() error:&e];
    if (!_player) { NSLog(@"[APD] keepalive player init failed: %@", e); return; }
    _player.numberOfLoops = -1;                         // loop forever
    _player.volume = 0.0;
    [_player prepareToPlay];
    if (![_player play]) { NSLog(@"[APD] keepalive play failed"); return; }

    _running = YES;
    NSLog(@"[APD] keepalive active (silent-audio background hold)");
}

- (void)stop {
    if (!_running) return;
    [_player stop]; _player = nil;
    [[AVAudioSession sharedInstance] setActive:NO
        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    _running = NO;
}

@end
