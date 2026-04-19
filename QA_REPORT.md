# QA Report — HiveRemote iOS

**Date:** 2026-04-19  
**App:** HiveRemote · `com.irvcassio.HiveRemote` · v1.0.0 build 2  
**Tester:** Irv Cassio (physical device QA pending)  
**IPA:** `build/IPA-Dev/HiveRemote.ipa` (1.0 MB · `iphoneos` · iOS 16.0+)  
**Xcode:** 26.4.1 (17E202) · **macOS:** 26.4.1

---

## Overall QA Status

| Phase | Status |
|---|---|
| Build compilation | ✅ PASS — zero errors, zero warnings |
| Static code analysis (all 11 Swift files) | ✅ PASS |
| Physical device QA | ⏳ PENDING — devices not connected at time of last run |

**Physical device QA is the final gate before Full PASS.**  
Devices identified: **Hollywood** (iPhone 15 Pro Max · iPhone16,2) and **Irv's iPad** (iPad Pro 12.9" 3rd gen · iPad8,7).

---

## How to Install the Dev IPA

### Via Xcode Devices & Simulators (simplest)

1. Connect iPhone or iPad via USB.
2. Unlock the device; tap **Trust This Computer** if prompted.
3. In Xcode: **Window → Devices and Simulators** (⇧⌘2).
4. Select the device in the left panel.
5. Under **Installed Apps**, click **+** and choose `build/IPA-Dev/HiveRemote.ipa`.
6. Wait for the progress bar; the app icon appears on the home screen.

### Via Apple Configurator 2

1. Connect device via USB.
2. Open **Apple Configurator 2**.
3. Select the device → **Actions → Add → Apps**.
4. Choose `build/IPA-Dev/HiveRemote.ipa` → **Add**.

> **Device registration:** If the device UDID is not already in the development provisioning profile, add it at developer.apple.com → Devices, regenerate the profile, then rebuild the IPA with `xcodebuild -exportArchive` (see `BUILD_INSTRUCTIONS.md`).

---

## Physical Device Test Scenarios

### TC-1 — Safe-Area Insets on Dynamic Island iPhone

**Device:** Hollywood (iPhone 15 Pro Max — Dynamic Island)  
**Precondition:** App freshly installed; Hive tunnel URL configured in Setup screen.

**Steps:**
1. Launch app.
2. Observe the loading spinner — confirm it does **not** overlap the Dynamic Island cutout at the top.
3. After the Hive dashboard loads, scroll the web content to the top.
4. Confirm the top of the web content is below the Dynamic Island (status bar area) — no content hidden behind the pill.
5. Confirm the **LAN** or **Cloud** status capsule in the bottom-right corner is above the home indicator swipe bar (not clipped or behind it).
6. Rotate to landscape. Confirm status capsule repositions to the right side above the home indicator.

**Pass criteria:** No content obscured by Dynamic Island; status capsule always visible; no scroll bounce revealing the app background color.

**Result:** ☐ PASS / ☐ FAIL — Notes: _______________

---

### TC-2 — LAN Path Used on Same WiFi

**Device:** Hollywood (iPhone) or Irv's iPad  
**Precondition:** Mac running Hive server is on the same WiFi network as the test device.

**Steps:**
1. Ensure Mac and device are on the same WiFi SSID.
2. Force-quit HiveRemote if running; relaunch from home screen.
3. Watch the status capsule in the bottom-right corner during the ~2-second LAN probe window.
4. Confirm capsule shows green **"LAN"** label (not blue **"Cloud"**).
5. In Safari on the device, confirm `http://hive.local:8123` resolves (this verifies mDNS works on your network). If it does NOT resolve in Safari, the app will also fall back to Cloud — that is correct behavior (see QA-006 note below).
6. Open Hive settings from within the web UI and confirm the URL bar (if visible in debug) shows `hive.local` not the Cloudflare tunnel hostname.

**Pass criteria:** Status capsule shows green **"LAN"** when Hive server is reachable on the local network.

**Result:** ☐ PASS / ☐ FAIL / ☐ N/A (mDNS blocked on this network — see QA-006) — Notes: _______________

---

### TC-3 — Cloudflare Tunnel Used on Cellular

**Device:** Hollywood (iPhone) — cellular required  
**Precondition:** App configured with a valid Cloudflare tunnel URL and service-token credentials.

**Steps:**
1. Disable WiFi on the device (Settings → WiFi → off). Device must be on LTE/5G only.
2. Force-quit HiveRemote; relaunch.
3. Confirm status capsule shows blue **"Cloud"** label.
4. Confirm Hive dashboard loads successfully (Cloudflare tunnel is reachable).
5. Re-enable WiFi. Within ~5 seconds, watch if capsule switches back to green **"LAN"** (if Mac is on same network — confirms mid-session network switch path TC-3 from static analysis also works at runtime).

**Pass criteria:** Blue "Cloud" capsule on cellular; dashboard loads without auth errors; capsule switches to "LAN" when WiFi restored (if Mac is on same network).

**Result:** ☐ PASS / ☐ FAIL — Notes: _______________

---

### TC-4 — Offline Native Overlay on Airplane Mode

**Device:** Hollywood (iPhone) or Irv's iPad  
**Precondition:** App running with dashboard loaded.

**Steps:**
1. Launch app; wait for Hive dashboard to fully load.
2. Enable **Airplane Mode** (Settings → Airplane Mode, or Control Center).
3. Observe the app within 1–2 seconds.
4. Confirm a **native overlay** appears: blurred backdrop, `wifi.slash` icon, "No Internet Connection" title, "Hive will reconnect when you're back online." subtitle. The web content should be obscured — this is NOT a browser error page.
5. Disable Airplane Mode.
6. Confirm the overlay fades out and Hive dashboard reloads automatically.

**Pass criteria:** Native UIKit overlay (not a web page) appears within ~2 seconds of going offline; overlay dismisses and page reloads on reconnection.

**Result:** ☐ PASS / ☐ FAIL — Notes: _______________

---

### TC-5 — iPad Orientation Layout

**Device:** Irv's iPad (iPad Pro 12.9" 3rd gen)  
**Precondition:** App installed and configured on iPad.

**Steps:**
1. Launch app in **portrait** orientation.
2. Confirm status capsule is visible in the bottom-right (above home indicator).
3. Confirm Hive dashboard fills the full screen with correct safe-area insets (no content behind status bar at top; no content under home bar at bottom).
4. Rotate iPad to **landscape left**.
5. Confirm layout reflows: status capsule relocates to bottom-right, safe-area insets on sides are respected (no content under the side bezel).
6. Rotate to **landscape right**. Confirm layout correct again.
7. Rotate back to **portrait**. Confirm no layout artifacts.
8. Open the Settings sheet (gear icon or Settings button). Confirm sheet opens and is usable in both orientations.

**Pass criteria:** No broken layout in any of the four orientations; status capsule always visible and not clipped; Settings sheet usable in all orientations.

**Result:** ☐ PASS / ☐ FAIL — Notes: _______________

---

### TC-6 — CF Auth Session Persists After Backgrounding

**Device:** Hollywood (iPhone) or Irv's iPad  
**Precondition:** App configured with Cloudflare tunnel; dashboard loaded via tunnel (use cellular or block LAN).

**Steps:**
1. Launch app; confirm Hive dashboard loads via Cloud path (blue capsule).
2. Press the **Home button** (or swipe up on Face ID devices) to background the app.
3. Wait **60 seconds** (to ensure the app is truly backgrounded and potentially memory-pressured).
4. Return to HiveRemote from the App Switcher or home screen icon.
5. Confirm the Hive dashboard is still showing the **same content** — no blank page, no CF login redirect, no "Connection Error" overlay.
6. Interact with the dashboard (navigate to a different HA view and back) to confirm the CF session is active.
7. **Extended test (optional):** Background for 10 minutes, then return. Confirm CF session is still valid.

**Pass criteria:** Content persists after backgrounding; no re-authentication required; no blank or error screen on foreground.

**Result:** ☐ PASS / ☐ FAIL — Notes: _______________

---

## Issues Summary

### Known Issues (from Static Analysis)

| ID | Severity | Description | Resolution |
|---|---|---|---|
| QA-001 | Medium | Double `loadHive()` on reconnect — `updateOfflineOverlay` completion + `handleNetworkModeChange` fire within ~2 s. Extra network round-trip; no crash, no stuck state. | `HiveWebViewController.swift:504–515` |
| QA-002 | Low | No proactive CF session freshness check on foreground. Stale content shows until a navigation bounces to CF login, which then auto-re-auths correctly. | `HiveWebViewController.swift:494–496` |
| QA-003 | Low | `UIRequiresFullScreen = true` disables Slide Over and Split View on iPad. Clarify intent before App Store submission. | `Info.plist` |
| QA-004 | Required | `NSPrivacyPolicyURL` is `https://www.example.com/hive-remote-privacy` — placeholder must be replaced before App Store submission. | `Info.plist` |
| QA-005 | Info | Pinch-to-zoom unconditionally disabled in non-DEBUG builds. May affect accessibility for dense HA dashboards on small screens. | `HiveWebViewController.swift:107` |
| QA-006 | Info | Default LAN host `hive.local` relies on mDNS/Bonjour. Fails on networks blocking multicast. User must manually configure IP in Settings. | `NetworkResolver.swift:78` |
| QA-007 | Low | `WKWebsiteDataStore.removeData` is async; stale `CF_Authorization` could briefly persist if user starts re-setup immediately after disconnect. | `HiveConfig.swift:46-50` |

### Physical Device QA Findings

*To be filled in after running TC-1 through TC-6 above.*

| ID | TC | Severity | Description |
|---|---|---|---|
| — | — | — | *(none yet — physical QA pending)* |

---

## QA Sign-Off Checklist

| Test | Result |
|---|---|
| Build compilation | ✅ PASS — zero errors, zero warnings |
| Static analysis — LAN routing (TC-1 code) | ✅ PASS (code-verified) |
| Static analysis — Cloudflare fallback (TC-2 code) | ✅ PASS (code-verified) |
| Static analysis — Network switch recovery (TC-3 code) | ✅ PASS (code-verified) |
| Static analysis — CF auth re-injection (TC-4 code) | ✅ PASS (code-verified) |
| Static analysis — Background/foreground session (TC-5 code) | ✅ PASS (code-verified) |
| Static analysis — Offline native error screen (TC-6 code) | ✅ PASS (code-verified) |
| Static analysis — iPad orientation layout (TC-7 code) | ✅ PASS (code-verified) |
| **TC-1 Physical — Safe-area insets on Dynamic Island** | ⏳ PENDING |
| **TC-2 Physical — LAN path on same WiFi** | ⏳ PENDING |
| **TC-3 Physical — Cloudflare tunnel on cellular** | ⏳ PENDING |
| **TC-4 Physical — Offline native overlay** | ⏳ PENDING |
| **TC-5 Physical — iPad orientation layout** | ⏳ PENDING |
| **TC-6 Physical — CF auth session after backgrounding** | ⏳ PENDING |

**Overall QA result: CONDITIONAL PASS → Full PASS pending TC-1 through TC-6 on physical devices.**

---

## Simulator Environment Note

`CoreSimulatorService` is not running (version mismatch: system has 1051.49, Xcode 26.4.1 requires 1051.50). All `simctl` operations hang. Physical devices are the only viable runtime test path.

**Known paired devices (not connected at last run):**

| Name | Model | Identifier |
|---|---|---|
| Hollywood | iPhone 15 Pro Max (iPhone16,2) | B9439C79-DD6E-5473-AFED-344DC763718E |
| Irv's iPad | iPad Pro 12.9" 3rd gen (iPad8,7) | 72F8D0A5-D684-56C4-9795-507391AEF269 |
| iPad mini | iPad mini 6th gen (iPad14,1) | 450D3001-D662-5B2C-8A54-3A247C4A74A1 |

To check if device is connected: `xcrun devicectl list devices`

---

**Signed:** QA Agent · 2026-04-19  
**Build:** HiveRemote v1.0.0 build 2 · `iphoneos` · Release-signed (Apple Development cert)  
**IPA:** `build/IPA-Dev/HiveRemote.ipa` (1.0 MB) — ready for sideload to registered devices
