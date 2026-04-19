# Hive-iOS Codebase Audit

**Updated:** 2026-04-19  
**Audited commit:** e948543 (feat: add NetworkResolver for LAN-first routing with Cloudflare fallback)  
**Project:** HiveRemote (com.irvcassio.HiveRemote)  
**Target:** iOS 16.0+, Swift 5.10, UIKit + SwiftUI

---

## Executive Summary

The codebase is in substantially better shape than the previous audit (2026-04-18). All prior P0/P1 issues have been resolved: `isInspectable` is gated behind `#if DEBUG`, error overlays are wired up, `WKUIDelegate` is fully implemented, safe-area CSS variables are injected at document start, the bottom capsule uses `safeAreaLayoutGuide`, scroll bounce is disabled, all required privacy strings are present, and LAN discovery (`NetworkResolver`) is live.

**Four open issues remain that are worth fixing before App Store submission:**

1. `NSPrivacyPolicyURL` is a placeholder URL — App Review will reject it (P0).
2. `LANSSLBypass` accepts self-signed certs from any host, not just LAN ranges — security gap (P1).
3. `SetupView` renders behind safe areas due to `.ignoresSafeArea()` on `ContentView`'s `Group` (P1).
4. LAN host edits are silently lost if the user swipe-dismisses the Settings sheet (P2).

---

## Resolved Since Previous Audit ✅

All issues from the 2026-04-18 audit have been addressed:

| Was | Now |
|-----|-----|
| `isInspectable = true` unconditional | Gated `#if DEBUG` — `HiveWebViewController.swift:170` |
| Error delegates only `print()` | `showError()` called in both failure delegates — `HiveWebViewController.swift:582-598` |
| No `WKUIDelegate` | Fully implemented with native `UIAlertController` — `HiveWebViewController.swift:613-653` |
| Safe-area insets not injected | `WKUserScript` at `documentStart` sets `--sat/sab/sal/sar` CSS vars — `HiveWebViewController.swift:112-145` |
| Bottom capsule hardcoded 20pt | Anchored to `safeAreaLayoutGuide.bottomAnchor` — `HiveWebViewController.swift:409` |
| `bounces = true` | `bounces = false` — `HiveWebViewController.swift:153` |
| Missing privacy strings | `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSLocalNetworkUsageDescription` all in `Info.plist` |
| `allowFileAccessFromFileURLs` private KVC | Removed |
| `CFBundleShortVersionString` hardcoded "1.0" | Resolves to `$(MARKETING_VERSION)` = `"1.0.0"` |
| `TARGETED_DEVICE_FAMILY: "1"` drift | Both `project.yml` and target settings show `"1,2"`; `UIRequiresFullScreen: true` added |
| Polling anti-pattern (`while webView == nil`) | Replaced with UIKit lifecycle — `viewDidAppear` → `loadHive()` |
| Custom UA replaced full Safari UA | `customUserAgent` not set; WebKit default UA used |
| Viewport meta not injected | Injected via `WKUserScript` alongside safe-area vars |
| Stale cookies on disconnect | `WKWebsiteDataStore.default().removeData(...)` called in `HiveConfig.clear()` — `HiveConfig.swift:48` |
| Orange launch screen flash | `LaunchBackground` color set matches app background `#F5F0E6` |
| LAN discovery not implemented | `NetworkResolver` live with 2-second timeout and self-signed TLS bypass |

---

## 1. App Store Submission Gaps

### 1.1 `NSPrivacyPolicyURL` is a Placeholder — **P0, BLOCKS REVIEW**

**File:** `HiveRemote/Info.plist:46`

```xml
<key>NSPrivacyPolicyURL</key>
<string>https://www.example.com/hive-remote-privacy</string>
```

App Store Review checks that this URL resolves to a real, reachable privacy policy. `example.com` is a reserved domain and will 404. The app will be rejected.

**Fix:** Host a real privacy policy (even a minimal one-page document) and update `project.yml`:
```yaml
NSPrivacyPolicyURL: "https://yourrealdomain.com/privacy"
```

---

### 1.2 Missing `PrivacyInfo.xcprivacy` — **P1**

**File:** absent

Since iOS 17.2 / Xcode 15, Apple requires a Privacy Manifest (`PrivacyInfo.xcprivacy`) for apps that access certain "required reason APIs". The app uses:
- `UserDefaults` — requires `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (app functionality)
- `WKWebsiteDataStore` — no manifest category, but the manifest itself must still exist

Without this file, the App Store upload produces a warning (currently) and will become a hard error in 2025 enforcement cycles.

**Fix:** Add `HiveRemote/PrivacyInfo.xcprivacy` to the target with:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
  </array>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyTracking</key>
  <false/>
</dict>
</plist>
```

---

## 2. Security Issues

### 2.1 `LANSSLBypass` Accepts Self-Signed Certs from Any Host — **P1**

**File:** `NetworkResolver.swift:134–147`

```swift
private final class LANSSLBypass: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: ...) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))  // no host check
    }
}
```

`LANSSLBypass` does not check that the challenged host is actually a local/private IP or `.local` hostname. An attacker on the same network who intercepts a `hive.local` mDNS response (DNS poisoning / mDNS spoofing) can redirect the probe to a server with any self-signed cert; this delegate will accept it.

The `WKNavigationDelegate` in `HiveWebViewController` has the same issue at line 527–538 — `isLocalHost()` is checked there before bypassing, which is correct. But `LANSSLBypass` has no equivalent guard.

**Fix:** Reuse or mirror the `isLocalHost()` check in `LANSSLBypass`:
```swift
let host = challenge.protectionSpace.host
guard isLocalHost(host) else {
    completionHandler(.performDefaultHandling, nil)
    return
}
```
Since `LANSSLBypass` is a private class inside `NetworkResolver.swift`, add a private `isLocalHost` helper or extract the existing one from `HiveWebViewController.swift:601` to a shared location.

---

### 2.2 `isLocalHost` Misses `127.0.0.1` and Link-Local Range — **P2**

**File:** `HiveWebViewController.swift:601–608`

```swift
private func isLocalHost(_ host: String) -> Bool {
    if host.hasSuffix(".local") || host == "localhost" { return true }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    return octets[0] == 10
        || (octets[0] == 172 && (16...31).contains(octets[1]))
        || (octets[0] == 192 && octets[1] == 168)
}
```

Missing:
- `127.0.0.1` (IPv4 loopback) — `localhost` string is caught but the IP form is not
- `169.254.x.x` (link-local / Zeroconf) — common for direct device-to-device connections
- IPv6 addresses (`::1`, `fc00::/7` ULA) — not a current concern but worth noting

**Fix:**
```swift
return octets[0] == 10
    || octets[0] == 127
    || (octets[0] == 169 && octets[1] == 254)
    || (octets[0] == 172 && (16...31).contains(octets[1]))
    || (octets[0] == 192 && octets[1] == 168)
```

---

## 3. UI/UX Gaps

### 3.1 `.ignoresSafeArea()` on `ContentView`'s `Group` Breaks `SetupView` — **P1**

**File:** `ContentView.swift:35`

```swift
Group {
    if config.isConfigured {
        NavigationStack { HiveWebViewContainer(...) }
    } else {
        SetupView()         // ← also affected
    }
}
.ignoresSafeArea()          // line 35
```

`.ignoresSafeArea()` propagates to both branches. For `HiveWebViewContainer` this has no effect (the UIKit VC uses `view.topAnchor`/`view.bottomAnchor` constraints directly). But `SetupView` — the tunnel-setup form — renders behind the Dynamic Island (top) and home indicator (bottom). First-run users enter their credentials with the text fields partially hidden.

**Fix:** Remove `.ignoresSafeArea()` from the `Group`. The WebView is already full-bleed via its UIKit constraints:
```swift
// Remove: .ignoresSafeArea()
```
If full-bleed is required only for the WebView branch, apply it there: `NavigationStack { ... }.ignoresSafeArea()`.

---

### 3.2 Full-Screen Loading Overlay During Mid-Session Re-Probe — **P2**

**File:** `HiveWebViewController.swift:447–453`

```swift
case .resolving:
    loadingOverlay.isHidden = false    // hides all web content
    errorOverlay.isHidden = true
```

When the app comes back from the background, `NetworkResolver` starts re-probing (up to 2 seconds per candidate × 3 candidates = up to 6 seconds in theory, though `withTaskGroup` races them). During this time, the full-screen loading overlay completely hides the web content the user was viewing. They see a spinner where their app was.

**Fix:** Only show the full-screen loading overlay on initial load (`!hasLoaded`). For mid-session re-probes, keep the WebView content visible and update only the network badge:
```swift
case .resolving:
    if !hasLoaded {
        loadingOverlay.isHidden = false
    }
    // Badge already updated by updateNetworkBadge()
    errorOverlay.isHidden = true
```

---

### 3.3 LAN Host Edits Lost on Sheet Swipe-Dismiss — **P2**

**File:** `SettingsView.swift:35–40`, `73–77`

`saveLanHost()` is called only on:
1. "Done" toolbar button tap
2. Keyboard "Return" / `onSubmit`

If the user edits the LAN host field and swipe-dismisses the sheet (the system sheet dismiss gesture), the change is discarded silently. `UserDefaults` retains the old value; the resolver is never re-triggered.

**Fix:** Add `.onDisappear` to the `NavigationStack`:
```swift
NavigationStack { ... }
    .onDisappear { saveLanHost() }
```

---

## 4. Code Quality

### 4.1 `@Published` Mutation from Background Task — **P2**

**File:** `NetworkResolver.swift:75`

```swift
private func performResolve() async {
    guard let tunnelURL else { return }
    mode = .resolving      // line 75 — may not be on main actor
```

`performResolve()` is called via `Task { await performResolve() }` from `resolve()`. `Task { }` creates an unstructured task that inherits the actor context of the call site. `resolve()` is documented as "safe to call from main thread" but is not annotated `@MainActor`. Without annotation, the compiler cannot guarantee `performResolve` runs on the main actor. Publishing `@Published` changes off the main thread causes SwiftUI runtime warnings (`Publishing changes from background threads is not allowed`) in Xcode 14+.

**Fix:** Annotate `NetworkResolver` with `@MainActor`, or annotate just `performResolve`:
```swift
@MainActor
private func performResolve() async { ... }
```
And update `pathMonitor.pathUpdateHandler` to dispatch to main actor instead of `DispatchQueue.main.async`.

---

### 4.2 Deprecated `.onChange(of:)` Closure Signature — **P3**

**File:** `ContentView.swift:26–30`

```swift
.onChange(of: config.tunnelURL) { _ in   // iOS 14 signature — deprecated in iOS 17
    if let url = config.baseURL {
        networkResolver.start(tunnelURL: url)
    }
}
```

With `deploymentTarget: iOS 16.0`, this compiles but generates a deprecation warning in Xcode 16. The iOS 17 form:
```swift
.onChange(of: config.tunnelURL) { _, _ in ... }
// or:
.onChange(of: config.tunnelURL) { oldValue, newValue in ... }
```

---

### 4.3 Redundant `NWPathMonitor` Instances — **P3**

**Files:** `ConnectionMonitor.swift:9`, `NetworkResolver.swift:39`

Two `NWPathMonitor` instances run simultaneously, both watching the same network path. `ConnectionMonitor` publishes `isConnected`; `NetworkResolver` also monitors path changes to trigger re-probing. `NetworkResolver` already tracks connectivity implicitly via `mode`. The `isNetworkConnected` property on `HiveWebViewController` drives the offline overlay — this could be derived from `networkResolver.mode == .resolving` after the initial load, eliminating `ConnectionMonitor` entirely.

This is a minor efficiency note, not a bug. Both monitors are cheap on iOS.

---

### 4.4 Unnecessary `NavigationStack` in `ContentView` — **P4**

**File:** `ContentView.swift:12`

```swift
NavigationStack {
    HiveWebViewContainer(showSettings: $showSettings)
        ...
}
```

`HiveWebViewController.viewWillAppear` immediately hides the navigation bar. There is no push navigation — Settings is presented as a sheet. `SettingsView` has its own `NavigationStack`. The outer `NavigationStack` in `ContentView` adds a `UINavigationController` to the hierarchy for no functional benefit.

**Fix:** Remove the `NavigationStack` wrapper; present `SettingsView` as a sheet directly from `HiveWebViewContainer`. (Low-priority — no user-visible effect.)

---

## Prioritized Change Manifest

| Priority | Issue | File | Line(s) | Effort |
|----------|-------|------|---------|--------|
| **P0** | `NSPrivacyPolicyURL` is placeholder — blocks App Review | `Info.plist` / `project.yml` | 46 | 30 min |
| **P1** | Missing `PrivacyInfo.xcprivacy` — required reason API (UserDefaults) | new file | — | 20 min |
| **P1** | `LANSSLBypass` accepts self-signed certs from any host — no local-host guard | `NetworkResolver.swift` | 134–147 | 30 min |
| **P1** | `.ignoresSafeArea()` on `Group` breaks `SetupView` safe areas | `ContentView.swift` | 35 | 5 min |
| **P2** | `isLocalHost` misses `127.0.0.1` and `169.254.x.x` | `HiveWebViewController.swift` | 601–608 | 10 min |
| **P2** | Full-screen overlay shown during mid-session re-probe (jarring) | `HiveWebViewController.swift` | 447–453 | 15 min |
| **P2** | LAN host edits lost on swipe-dismiss of Settings sheet | `SettingsView.swift` | 73–77 | 10 min |
| **P2** | `performResolve` publishes `@Published` potentially off main actor | `NetworkResolver.swift` | 75 | 20 min |
| **P3** | `.onChange(of:)` deprecated closure form (compile warning) | `ContentView.swift` | 26 | 5 min |
| **P3** | Redundant dual `NWPathMonitor` instances | `ConnectionMonitor.swift`, `NetworkResolver.swift` | — | 1 hr |
| **P4** | Unnecessary `NavigationStack` in `ContentView` | `ContentView.swift` | 12 | 20 min |

---

## Network Implementation Summary (current state)

**URL loading flow:**
1. `ContentView.onAppear` → `networkResolver.start(tunnelURL:)` starts `NWPathMonitor` and probes LAN candidates concurrently (2s timeout, `HEAD` request).
2. `NetworkResolver` publishes `.lan(url:)` or `.tunnel(url:)` to `@Published var mode`.
3. `HiveWebViewContainer.updateUIViewController` propagates `networkMode` to `HiveWebViewController`.
4. `handleNetworkModeChange()` calls `loadHive()` when a resolved URL's host differs from the current WebView host.
5. `loadHive()` loads the LAN URL directly (no extra headers) or the tunnel URL with `CF-Access-Client-Id` / `CF-Access-Client-Secret` headers.
6. `WKNavigationDelegate.decidePolicyFor` intercepts Cloudflare Access redirects and re-issues the tunnel request with auth headers. Also intercepts tunnel-host navigation without headers and re-issues with them.

**No hardcoded URLs.** The tunnel URL is stored in `UserDefaults` under `"hive_tunnel_url"`. The LAN hostname is stored under `"hive_lan_host"` (default `"hive.local"`).

**Cloudflare auth:** `CF_Authorization` cookie is persisted in `WKWebsiteDataStore.default()`. Service-token headers are injected on tunnel-host requests. Cleared on `HiveConfig.clear()`.

**LAN probe candidates:** `http://hive.local:8123`, `https://hive.local:8123`, `http://hive.local` — raced concurrently, first success wins. Self-signed TLS bypassed for all (see §2.1 security issue).
