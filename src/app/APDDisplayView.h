#import <UIKit/UIKit.h>

/* Full-screen view backed by an AVSampleBufferDisplayLayer.
 * Feed it Annex-B (00 00 00 01 start-code) H.264/H.265 NAL units as delivered
 * by UxPlay's video_process callback; it builds CMSampleBuffers and displays them. */
@interface APDDisplayView : UIView
- (void)enqueueAnnexB:(const uint8_t *)data length:(int)length isH265:(BOOL)isH265;
- (void)reset;                 // drop param sets + flush (on new connection / codec change)
- (void)showStatus:(NSString *)text;   // overlay text ("Waiting for Mac…")
@end
