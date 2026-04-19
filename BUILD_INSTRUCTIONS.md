# HiveRemote iOS — Build & Distribution Instructions

**Last updated:** 2026-04-19  
**App:** HiveRemote · `com.irvcassio.HiveRemote`  
**Version:** 1.0.0 · **Build:** 2  
**Team ID:** L4BZ3L6LJR  
**Xcode:** 26.4.1 (17E202) · **macOS:** 26.4.1

---

## Current Build Status

| Step | Result | Detail |
|---|---|---|
| QA sign-off | ✅ CONDITIONAL PASS | No blocking defects; runtime simulator blocked by CoreSimulator mismatch |
| Build number increment | ✅ Done | 1 → 2 (in `HiveRemote/Info.plist` and `project.yml`) |
| `xcodebuild clean build` (Release/iphoneos) | ✅ PASS | Zero errors, zero warnings |
| `xcodebuild archive` (Release) | ✅ SUCCEEDED | `build/Hive.xcarchive` — signed Development cert |
| App Store IPA export | ❌ BLOCKED | No Apple Distribution cert / no App Store provisioning profile |
| Development IPA export | ✅ SUCCEEDED | `build/IPA-Dev/HiveRemote.ipa` (1.0 MB) |
| App Store Connect upload | ❌ BLOCKED | Requires distribution cert + App Store Connect record |
| TestFlight availability | ❌ BLOCKED | Upload step blocked |
| Physical device install | 🟡 AVAILABLE (dev only) | Use Finder sideload with dev IPA; device must be in dev profile |

---

## Quick Reference — Commands That Work Today

```bash
# Clean release build (no signing)
xcodebuild clean build \
  -project HiveRemote.xcodeproj \
  -scheme HiveRemote \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Archive (development-signed — succeeds today)
xcodebuild archive \
  -project HiveRemote.xcodeproj \
  -scheme HiveRemote \
  -configuration Release \
  -archivePath ./build/Hive.xcarchive \
  -allowProvisioningUpdates

# Development IPA export (sideload to registered devices)
xcodebuild -exportArchive \
  -archivePath ./build/Hive.xcarchive \
  -exportOptionsPlist ./build/ExportOptionsDev.plist \
  -exportPath ./build/IPA-Dev \
  -allowProvisioningUpdates
```

**Development IPA location:** `build/IPA-Dev/HiveRemote.ipa`

---

## Blocker: Apple Distribution Certificate Required

### Root Cause

The machine has only **development** code signing certificates for team `L4BZ3L6LJR`:

```
Apple Development: Irv Cassio (U3VK59WVPJ)   ← present
Apple Distribution: Irv Cassio (L4BZ3L6LJR)  ← MISSING
```

App Store archiving and export require an **Apple Distribution** certificate. The `xcodebuild -exportArchive` command with `method: app-store-connect` fails with:

```
error: exportArchive No Accounts
error: exportArchive No profiles for 'com.irvcassio.HiveRemote' were found
```

### Pre-Requisites Checklist

Before running a full App Store build, complete every item below:

- [ ] **Apple Developer Program enrollment** — Team `L4BZ3L6LJR` must have an active paid membership ($99/year). Verify at developer.apple.com/account.
- [ ] **Apple Distribution certificate** — Create in Xcode → Settings → Accounts → `L4BZ3L6LJR` → Manage Certificates → `+` → Apple Distribution. Or in the Apple Developer Portal under Certificates.
- [ ] **App Store provisioning profile** — In the Apple Developer Portal, create an App Store distribution provisioning profile for bundle ID `com.irvcassio.HiveRemote`, linked to the Apple Distribution cert. Download and double-click to install, OR let Xcode manage it automatically after adding the distribution cert.
- [ ] **App ID registered** — `com.irvcassio.HiveRemote` must exist in the Apple Developer Portal under Identifiers.
- [ ] **App Store Connect record** — Create a new app in App Store Connect (appstoreconnect.apple.com) with bundle ID `com.irvcassio.HiveRemote`, name "Hive Remote", primary language and category set.
- [ ] **Privacy policy URL** — Replace the placeholder in `HiveRemote/Info.plist` (key `NSPrivacyPolicyURL`, currently `https://www.example.com/hive-remote-privacy`) with a real URL before submission.

---

## Full App Store Distribution Workflow (Once Unblocked)

### Step 1 — Increment Build Number

For each new submission, increment `CFBundleVersion` in `HiveRemote/Info.plist` and `CURRENT_PROJECT_VERSION` in `project.yml`. App Store Connect rejects duplicate build numbers.

Current: **Build 2** (version 1.0.0). Next submission: Build 3.

### Step 2 — Archive for Distribution

```bash
xcodebuild archive \
  -project HiveRemote.xcodeproj \
  -scheme HiveRemote \
  -configuration Release \
  -archivePath ./build/Hive.xcarchive \
  -allowProvisioningUpdates
```

After prerequisites are met, the `SigningIdentity` in `build/Hive.xcarchive/Info.plist` must read **`Apple Distribution: Irv Cassio`** (not `Apple Development`). Verify before continuing.

### Step 3 — Export IPA for App Store

Create `build/ExportOptions.plist` (already created at that path) with `method: app-store-connect`, then:

```bash
xcodebuild -exportArchive \
  -archivePath ./build/Hive.xcarchive \
  -exportOptionsPlist ./build/ExportOptions.plist \
  -exportPath ./build/IPA \
  -allowProvisioningUpdates
```

Expected output: `build/IPA/HiveRemote.ipa`

### Step 4 — Upload to App Store Connect

#### Option A — xcrun altool (CLI, available on this machine v26.30.4)

Using App Store Connect API Key (recommended — no 2FA interruption):

```bash
# Generate an App Store Connect API Key at:
# appstoreconnect.apple.com → Users → Integrations → API Keys

xcrun altool --upload-app \
  --type ios \
  --file ./build/IPA/HiveRemote.ipa \
  --apiKey  <YOUR_API_KEY_ID> \
  --apiIssuer <YOUR_ISSUER_ID>
```

Place the downloaded `.p8` key file in `~/.private_keys/AuthKey_<KEY_ID>.p8` (altool finds it automatically).

Using Apple ID + app-specific password (alternative):

```bash
# Generate app-specific password at appleid.apple.com → Security
xcrun altool --upload-app \
  --type ios \
  --file ./build/IPA/HiveRemote.ipa \
  --username <your@apple.id> \
  --password <app-specific-password>
```

#### Option B — Xcode Organizer (manual, simplest)

1. Open Xcode.
2. Menu: **Window → Organizer** (⇧⌘O).
3. Select the `Hive.xcarchive` dated today.
4. Click **Distribute App**.
5. Choose **App Store Connect** → **Upload**.
6. Follow the wizard (automatic signing handles profile selection).

### Step 5 — Verify TestFlight Build

After upload (allow 5–30 minutes for Apple processing):

1. Log in to appstoreconnect.apple.com.
2. Navigate to **Apps → Hive Remote → TestFlight**.
3. Confirm build 2 (or current build number) appears with status **Ready to Test**.
4. Add internal testers or create an external test group.

### Step 6 — Physical Device Install

#### TestFlight (after Step 5)

1. Install TestFlight from the App Store on the device.
2. Accept the email invitation or open the public TestFlight link.
3. Install HiveRemote from within TestFlight.

#### Development Sideload (available today — no distribution cert needed)

The development IPA at `build/IPA-Dev/HiveRemote.ipa` can be installed on any device **registered in the development provisioning profile**:

**Via Finder (macOS Ventura+):**
1. Connect iPhone/iPad via USB.
2. Open Finder → select device in sidebar.
3. Click the **Files** tab (or drag IPA to the General pane in some Xcode versions).
4. Alternatively: open Xcode → **Window → Devices and Simulators** → select device → drag `HiveRemote.ipa` onto the Installed Apps list.

**Via Apple Configurator 2 (free on Mac App Store):**
1. Connect device.
2. Select device in Apple Configurator 2.
3. **Actions → Add → Apps** → select `HiveRemote.ipa`.

**Register device first:**
If the device is not already in the provisioning profile, add its UDID in the Apple Developer Portal (Devices section) and regenerate the provisioning profile, then rebuild the dev IPA.

---

## Pre-Submission Blockers from QA Report

These must be resolved before App Store Review:

| ID | Severity | Required Action |
|---|---|---|
| QA-004 | Required | Replace `NSPrivacyPolicyURL` placeholder (`https://www.example.com/hive-remote-privacy`) in `HiveRemote/Info.plist` with a real, publicly accessible privacy policy URL |
| QA-003 | Clarify intent | `UIRequiresFullScreen: true` disables Slide Over and Split View on iPad — confirm this is intentional before submission; App Review may require a justification or rejection if iPad multitasking is expected |

Non-blocking but recommended before submission:
- QA-001: Double `loadHive()` on network reconnect — low risk, extra round-trip only
- QA-005: Pinch-to-zoom disabled — consider enabling for accessibility on small screens
- QA-007: Async cookie removal race on disconnect — practically harmless

---

## Simulator Environment Note

Local CoreSimulatorService has a version mismatch:

```
Installed: 1051.49  (system framework)
Required:  1051.50  (Xcode 26.4.1)
```

All `simctl` operations (boot, list, install) hang indefinitely. To restore simulator support:
- Option A: macOS system update that aligns the framework version
- Option B: Test on physical devices (preferred for release validation anyway)
- Option C: Use a CI host (GitHub Actions `macos-latest`, Bitrise, CircleCI) with a matching Xcode/macOS image

---

## File Map

```
build/
├── Hive.xcarchive/              ← Release archive (development-signed, build 2)
│   └── Info.plist               ← SigningIdentity: Apple Development (NOT dist)
├── HiveRemote.xcarchive/        ← Previous archive (development-signed, build 1)
├── IPA-Dev/
│   └── HiveRemote.ipa           ← Development IPA, 1.0 MB — sideloadable today
├── ExportOptions.plist          ← App Store export config (use after dist cert obtained)
└── ExportOptionsDev.plist       ← Development export config

HiveRemote/Info.plist            ← Source of truth for CFBundleVersion (currently: 2)
project.yml                      ← XcodeGen config; CURRENT_PROJECT_VERSION: "2"
```
