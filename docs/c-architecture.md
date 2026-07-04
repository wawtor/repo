# iPad AirPlay Display — Architecture & Plan

Turn a jailbroken **iPad Air 2 (iOS 15.8.8, palera1n rootful)** into a wireless
**secondary display** for a Mac, using macOS's *built-in* AirPlay "Use as Separate
Display" — so there is **zero custom software on the Mac side**.

## Key insight (validated by research)
- macOS's "Use as Separate Display" is **not** gated to Apple-certified hardware.
  It is negotiated from what the receiver advertises in the AirPlay/RTSP handshake.
  Real-world proof: UxPlay Issue #58 (a non-Apple receiver got the "separate
  display" option from macOS).
- Therefore: build an **AirPlay video mirroring *receiver*** that runs *on the iPad*.
  The Mac's native Screen Mirroring does all the sender-side work.

## Why not a "tweak"?
This isn't a hook/patch of an existing process — it's a standalone receiver app.
The jailbreak's role is **persistent sideloading** (no 7-day resign) + optional
low-level display/awake control, not Substrate injection.

## Component reuse — fork UxPlay's `lib/`
UxPlay's `lib/` is a clean, self-contained C core with **no GStreamer dependency**:
- `fairplay_playfair.c` + `playfair/` — **FairPlay/SAPv2 auth** (the hard part, already done)
- `raop.c`, `raop_rtp_mirror.c`, `raop_handlers.h` — RAOP/RTSP server + mirror stream
- `pairing.c`, `srp.c`, `crypto.c` — pairing + crypto
- `mdnsd/` + `dnssd.c` — **bundled mDNS** (no Avahi needed)
- `llhttp/` — bundled HTTP parser
- **External deps: only `libcrypto` (OpenSSL) + `libplist`.**

GStreamer lives only in UxPlay's top-level renderer, which we **discard**.

## The seam: `struct raop_callbacks_s` (lib/raop.h)
Encoded video arrives via:
```c
void (*video_process)(void *cls, raop_ntp_t *ntp, video_decode_struct *data);
```
`video_decode_struct` (lib/stream.h):
```c
bool is_h265; int nal_count; unsigned char *data; int data_len;
uint64_t ntp_time_local; uint64_t ntp_time_remote;
```
Raw NAL units + codec flag + timestamps → feed straight into **VideoToolbox**.

## iOS front-end (what we write)
1. `raop_init()` with our callbacks; advertise via bundled mdnsd.
2. `video_process` → build CMSampleBuffer from NALs → `VTDecompressionSession`
   (H.264/H.265) → `CVImageBuffer`.
3. Render full-screen via `AVSampleBufferDisplayLayer` (simplest low-latency path).
4. `video_set_codec` / `video_report_size` handle codec + geometry.
5. Keep display awake, handle rotation, disconnect/reconnect. Audio optional (later).

## Toolchain
- No Xcode (CLT only, no iOS SDK). Cross-compile with **Theos** + an iPhoneOS SDK
  from the theos/sdks repo. `ldid` sign, `dpkg-deb` package.
- iPad already has: ldid, dpkg-deb, git, OpenSSL headers. Missing: compiler/SDK
  (that's why we build on the Mac, not on-device).

## Milestones (see task list)
1. **Validate** — build vanilla UxPlay on the Mac, confirm macOS offers "Use as
   Separate Display" over loopback. GO/NO-GO gate.
2. **Toolchain** — Theos + iOS SDK + signing, trivial app runs on iPad.
3. **lib port** — cross-compile UxPlay `lib/` core (libcrypto + libplist) for arm64.
4. **Front-end** — VideoToolbox decode + full-screen render + mDNS; shows in Mac menu.
5. **Package & test** — .deb, install, end-to-end extended-display, tune latency.

## Risks
- FairPlay working on iOS arm64 (mitigated: reuse UxPlay's proven code) — verify in M1.
- macOS offering separate-display in *this* setup — the M1 gate.
- libplist/libcrypto iOS cross-compile friction — M3.
- AVSampleBufferDisplayLayer latency/format quirks — M4.
