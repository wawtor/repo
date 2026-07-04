# AirPlay Display — iPad as a Mac secondary display

Turns a **jailbroken iPad Air 2 (iOS 15.8.8, palera1n rootful)** into a wireless
**secondary display** for a Mac, using macOS's built-in AirPlay Screen Mirroring —
including **"Use as Separate Display"** (true extended desktop). **No software on the
Mac side.**

It's a from-scratch **AirPlay video mirroring receiver** that runs on the iPad. It
reuses UxPlay's C protocol/FairPlay core (`libairplay.a`) and adds an iOS front-end that
decodes the H.264/H.265 stream with **VideoToolbox** and renders it full-screen via
`AVSampleBufferDisplayLayer`.

## Status: WORKING ✅
Mirror **and** separate-display confirmed end-to-end on real hardware.

## Layout
```
docs/c-architecture.md      full design + milestones
src/app/                    iOS app (Obj-C): main, AppDelegate, DisplayView, Receiver
src/c-build-libairplay.sh   cross-compile UxPlay lib/ -> build/ios/libairplay.a
src/c-build-app.sh          compile+link+sign the app  -> build/ios/AirPlayDisplay.app
src/c-deploy.sh             build + push + install + relaunch on the iPad (fast iterate)
src/c-package-deb.sh        package -> build/deb/*.deb
src/c-build-repo.sh         assemble Sileo repo -> build/repo/
vendor/UxPlay/              upstream source (protocol/FairPlay core we fork)
vendor/theos/               iOS cross-compile toolchain + iPhoneOS16.5 SDK
vendor/ios-deps/            libcrypto + libplist (headers+dylibs) pulled from the iPad
```

## Build from scratch
```sh
./src/c-build-libairplay.sh   # core static lib
./src/c-build-app.sh          # the .app
./src/c-package-deb.sh        # the .deb
./src/c-build-repo.sh         # the Sileo repo
```

## Install on the iPad
**Via the Sileo repo** (while the Mac is serving it on the LAN):
1. Sileo → Sources → **＋** → `http://<mac-ip>:8088/`
2. Install **AirPlay Display**.

**Or directly:** `dpkg -i com.wawtor.airplaydisplay_0.1_iphoneos-arm.deb`

## Use
1. Launch **AirPlay Display** on the iPad (it shows "Waiting for a Mac…").
2. On the Mac: **Control Center → Screen Mirroring → "… (Display)"**.
3. Open Screen Mirroring again → **Use as Separate Display** for extended desktop.

## Key implementation notes / gotchas
- `raop_init2` keyfile must be `""`, never `NULL` (`strlen` crash in ed25519 keygen).
- `raop_start_httpd` returns **1 on success** (negative = error), not 0.
- **All 33** `raop_callbacks_s` fields must be non-NULL or the handshake calls a NULL
  pointer and crashes; `report_client_request` must set `*admit = true`.
- Video arrives as **Annex-B** NALs (SPS/PPS prepended to the first frame) → converted to
  AVCC `CMSampleBuffer` → `AVSampleBufferDisplayLayer`.
- Binaries need a `platform-application` entitlement (`ldid -Sents.plist`) or AMFI kills
  them (`Killed: 9`). A Mac-side ldid signature with entitlements is honored on-device.
- "Use as Separate Display" is offered even with the default `model=AppleTV3,2` — no model
  spoof needed (matches UxPlay issue #58).
