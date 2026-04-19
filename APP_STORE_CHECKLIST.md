# App Store Submission Checklist — Hive Remote

**Version:** 1.0.0 (Build 1)  
**Bundle ID:** com.irvcassio.HiveRemote  
**Last Updated:** 2026-04-19

---

## ⛔ Hard Blockers — Manual Steps Required Before TestFlight

These three steps are human-gated and have no code component. Nothing automated can proceed until they are complete.

- [ ] **Privacy Policy URL** — Host a publicly accessible privacy policy page, then replace the placeholder `https://www.example.com/hive-remote-privacy` in `HiveRemote/Info.plist` key `NSPrivacyPolicyURL` (also in `project.yml`) with the real URL. App Review will reject any URL that 404s — `example.com` is reserved and will fail.

- [ ] **App Store Connect record** — Log in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com), create a new iOS app with:
  - Bundle ID: `com.irvcassio.HiveRemote`
  - Name: `Hive Remote`
  - Primary language: English
  - Primary category: Utilities

- [ ] **Distribution certificate + provisioning profile** — In Xcode → Settings → Accounts → team `L4BZ3L6LJR` → Manage Certificates, create an **Apple Distribution** certificate. Then in the [Apple Developer Portal](https://developer.apple.com/account/resources/profiles/list), create an **App Store** provisioning profile for `com.irvcassio.HiveRemote` and download it.

---

## Info.plist — Completed ✅

- [x] `CFBundleDisplayName` → "Hive Remote"
- [x] `CFBundleShortVersionString` → `$(MARKETING_VERSION)` = 1.0.0
- [x] `CFBundleVersion` → 1 (build 1)
- [x] `ITSAppUsesNonExemptEncryption` → false (no export compliance required)
- [x] `NSCameraUsageDescription` — "Hive uses your camera for video feeds and visual monitoring."
- [x] `NSMicrophoneUsageDescription` — "Hive uses your microphone for audio monitoring and two-way communication."
- [x] `NSLocalNetworkUsageDescription` — "Hive scans the local network to connect directly to your Hive server when available."
- [x] `NSBonjourServices` — `_http._tcp`, `_https._tcp` (required by App Review when using local network)
- [x] `NSAppTransportSecurity`
  - `NSAllowsArbitraryLoads` = false (HTTPS enforced for remote URLs)
  - `NSAllowsArbitraryLoadsInWebContent` = true (WebView loads arbitrary HTTPS)
  - `NSAllowsLocalNetworking` = true (LAN HTTP connections — required for hive.local)
- [x] `NSPrivacyPolicyURL` → placeholder `https://www.example.com/hive-remote-privacy` — **replace before submission**
- [x] `UIRequiredDeviceCapabilities` → `arm64`
- [x] `UIRequiresFullScreen` → true (opted out of iPad Split View multitasking)
- [x] `UILaunchScreen` → `UIColorName: LaunchBackground` (universal color #F5F0E6, covers all device sizes including iPhone SE and iPad Pro)

---

## Privacy Manifest — Completed ✅

- [x] `PrivacyInfo.xcprivacy` present and included in the target
  - `NSPrivacyAccessedAPITypes` → `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`
  - `NSPrivacyCollectedDataTypes` → empty (no data collected)
  - `NSPrivacyTracking` → false

---

## Code & Build — Completed ✅

- [x] `isInspectable = true` gated behind `#if DEBUG` — not exposed in Release
- [x] No private API symbols (`setValue:forKey:` with private keys removed; grepped clean)
- [x] `WKUIDelegate` implemented — JS `alert`/`confirm`/`prompt` surface as native dialogs
- [x] Error delegate dismisses loading spinner and shows error overlay
- [x] `bounces = false` — overscroll does not expose background
- [x] Safe-area CSS env() variables injected at document start
- [x] Control capsule anchored to `safeAreaLayoutGuide` — respects home indicator
- [x] `LANSSLBypass` guards `isLocalHost()` before accepting self-signed certs
- [x] `isLocalHost()` covers RFC-1918 + loopback (127.x) + link-local (169.254.x) + `.local` mDNS
- [x] Mid-session re-probe does not flash full-screen loading overlay over visible web content
- [x] LAN host edits saved on sheet swipe-dismiss (`.onDisappear`)
- [x] `NetworkResolver` annotated `@MainActor` — no background-thread `@Published` mutations
- [x] `UIColor.hiveBackground` extension defined in `HiveWebViewController.swift`
- [x] Deployment target: iOS 16.0
- [x] **BUILD SUCCEEDED** — Release, iphoneos SDK, zero errors, zero privacy/entitlement warnings

---

## App Store Connect — Required Before Submission

### Account & App Record
- [ ] Create app record in App Store Connect (appstoreconnect.apple.com)
- [ ] Select primary language (English)
- [ ] Set SKU (e.g., `hive-remote-ios-1`)
- [ ] Select content rights (you own or have licensed all content)

### App Information
- [ ] **Name:** "Hive Remote" (30 chars max)
- [ ] **Subtitle:** e.g., "Home automation at your fingertips" (30 chars max)
- [ ] **Category:** Utilities (primary), Productivity (secondary)
- [ ] **Privacy Policy URL:** Replace placeholder with real, publicly accessible URL before submission

### App Review Information
- [ ] Demo credentials or demo mode instructions — reviewer needs to test the app. Either:
  - Provide a test tunnel URL + Cloudflare service token credentials, OR
  - Implement a sandbox/demo mode that works without a real Hive server
- [ ] Notes for reviewer explaining that the app requires a self-hosted Home Assistant instance accessible via Cloudflare Tunnel

### Pricing & Availability
- [ ] Set price (Free or paid)
- [ ] Select territories

### Description & Metadata
- [ ] **App Description** (up to 4000 chars): Write a full description explaining what Hive Remote does, what server software it connects to, and that users need their own Hive/Home Assistant instance.
- [ ] **Keywords** (100 chars max): e.g., `home automation,hive,home assistant,cloudflare,local network,smart home`
- [ ] **Support URL:** A real URL (GitHub repo page, personal site, etc.)
- [ ] **Marketing URL** (optional)

### Screenshots (Required — cannot submit without these)

All screenshots must be PNG or JPEG, max 500 MB each.

| Device | Required Size | Notes |
|--------|--------------|-------|
| iPhone 6.9" (iPhone 16 Pro Max / 16 Plus) | 1320×2868 px | **Required** |
| iPhone 6.7" (iPhone 15 Pro Max) | 1290×2796 px | Can reuse 6.9" |
| iPad Pro 13" (M4) | 2064×2752 px | **Required** |
| iPad Pro 12.9" (6th gen) | 2048×2732 px | Can reuse M4 |

- At minimum you must provide iPhone 6.9" and iPad 13" screenshots.
- Recommended shots: loading state, main Hive dashboard, settings screen, error/offline screen.
- Use Simulator (iPhone 16 Pro Max and iPad Pro 13" M4) to capture at correct resolution.

### App Preview Videos (optional but recommended)
- Up to 3 previews per device type
- 15–30 seconds, landscape or portrait matching the device
- Must show actual app functionality (loading, navigating the Hive UI, settings)

---

## Pre-Submission Build Steps

1. Replace `NSPrivacyPolicyURL` placeholder with real URL in `project.yml` (regenerate project with `xcodegen` if used)
2. Provide real App Review credentials or demo account
3. Increment `CURRENT_PROJECT_VERSION` in `project.yml` each new build (currently: 2 — `CFBundleVersion` in Info.plist is hardcoded 1; keep in sync)
4. Archive: `Product → Archive` in Xcode (or `xcodebuild archive -scheme HiveRemote -sdk iphoneos`)
5. Validate archive in Xcode Organizer before uploading
6. Upload to App Store Connect via Xcode Organizer or `xcrun altool`

---

## Post-Launch

- [ ] Monitor crash reports in App Store Connect → Analytics
- [ ] Set up TestFlight beta group for internal testing before public release
- [ ] Consider adding `NSLocationWhenInUseUsageDescription` if location-aware automations are added later
