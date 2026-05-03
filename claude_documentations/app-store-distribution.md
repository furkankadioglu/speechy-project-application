# Mac App Store Distribution

Speechy now ships in two distribution channels:

| Channel | License model | Build flag | Validation |
|---------|---------------|------------|------------|
| **Direct** (speechy.frkn.com.tr) | Custom license keys + machine binding | (default) | `LicenseManager` → `/api/license/*` |
| **Mac App Store** | One-time purchase, Apple-managed | `-DAPP_STORE` | `AppStoreReceipt` → `/api/receipt/verify` |

A single `main.swift` codebase covers both. The compile-time flag `APP_STORE` selects which gate runs.

## Architecture

```
launch
  │
  ├─ #if APP_STORE
  │     AppStoreReceipt.gateOrExit()      // synchronous, before NSApp
  │       └─ if receipt missing → exit(173)
  │            └─ macOS prompts Apple ID → downloads receipt → relaunches
  │
  ├─ NSApplication.run
  │
  └─ AppDelegate.initializeApp
        ├─ #if APP_STORE
        │     AppStoreReceipt.shared.verifyOnline()
        │       ├─ POST receipt to backend
        │       ├─ backend → Apple verifyReceipt (production → sandbox fallback)
        │       └─ on success: cache 7 days, allow offline use
        └─ #else
              LicenseManager flow (existing)
```

## What `exit(173)` does

When a Mac App Store app exits with code 173, macOS interprets it as "receipt missing" and:

1. Prompts the user for their Apple ID
2. Authenticates against the App Store
3. If the user purchased the app, downloads a fresh `_MASReceipt/receipt`
4. Re-launches the binary

This is Apple's documented mechanism for receipt-based access control. We never need to roll our own auth flow.

## Receipt validation flow

`AppStoreReceipt` does both checks:

1. **Synchronous gate** (`gateOrExit`) — only checks that the receipt file exists. Cannot be bypassed because the OS injects the receipt; copying the .app bundle alone does not include it.
2. **Asynchronous verification** (`verifyOnline`) — sends the base64 receipt to our backend (`/api/receipt/verify`). Backend forwards to Apple, parses the response, and caches the transaction record.

The backend writes verified receipts to the `app_store_receipts` table. If Apple later marks a transaction as refunded (`cancellation_date` field present), the next verification cycle will flag the install as invalid and the app terminates.

## Sandbox limitations

App Store apps run in a sandbox. The following Speechy features need careful handling:

| Feature | Sandbox status | Notes |
|---------|----------------|-------|
| Microphone | OK (`com.apple.security.device.audio-input`) | |
| Network calls | OK (`com.apple.security.network.client`) | |
| File save dialogs | OK (`com.apple.security.files.user-selected.read-write`) | |
| Global hotkeys (Carbon `RegisterEventHotKey`) | **Risky** — works for app-local hotkeys, but global registration is gated by Accessibility permission which sandbox restricts. Test thoroughly before submitting. |
| Spotify / Apple Music AppleScript | Requires `com.apple.security.scripting-targets` + `com.apple.security.temporary-exception.apple-events`. Apple may reject; have a fallback ready. |
| `ioreg` for machine ID | **Won't run** — but App Store build doesn't need machine binding. |

If Apple rejects the global hotkey or AppleScript entitlements, the App Store build will need to drop those features or use alternative APIs. Consider this a likely review hurdle.

## Build commands

```bash
# Direct distribution (existing flow)
cd desktop/SpeechToText && ./build.sh
cd desktop/SpeechToText && ./build.sh --install
cd desktop/SpeechToText && ./build.sh --deploy

# Mac App Store
cd desktop/SpeechToText && ./build.sh --app-store
```

The `--app-store` build:

- Compiles with `-DAPP_STORE`
- Uses `Info.AppStore.plist` (sandboxed, with `LSApplicationCategoryType`, `ITSAppUsesNonExemptEncryption`, etc.)
- Uses `SpeechToText.AppStore.entitlements`
- Requires `3rd Party Mac Developer Application` and `3rd Party Mac Developer Installer` certificates in keychain
- Requires `Speechy_Mac_App_Store.provisionprofile` from App Store Connect
- Outputs `build-appstore/Speechy.app` and `build-appstore/Speechy.pkg`

Override cert names via env vars: `SPEECHY_MAS_APP_CERT`, `SPEECHY_MAS_INSTALLER_CERT`, `SPEECHY_MAS_PROFILE`.

## App Store Connect setup

1. App Store Connect → My Apps → New App
   - Bundle ID: `com.speechy.app` (must match `Info.AppStore.plist`)
   - Platform: macOS
   - Primary Language: Turkish
   - SKU: `speechy-macos`
2. Pricing: tier corresponding to your target price (e.g. $19.99). Single tier, no auto-renewal.
3. App Information → enter App Store Shared Secret (or skip — only needed for subscriptions)
4. Apple Small Business Program — apply if revenue under $1M/year for 15% commission instead of 30%.
5. App Review Information — provide reviewer notes explaining microphone use, AppleScript reasons, etc.
6. Build → upload via `xcrun altool`:

```bash
xcrun altool --upload-app --type osx \
    --file build-appstore/Speechy.pkg \
    --apple-id YOUR_APPLE_ID \
    --password APP_SPECIFIC_PASSWORD
```

## Backend

- **Migration**: `licensing/migrations/006_app_store_receipts.sql`
- **Route**: `POST /api/receipt/verify` (in `licensing/routes/receipt.php`)
- **Config**: `appstore_shared_secret` in `config.php` (optional for one-time purchases)

Run the migration before deploying:

```bash
ssh yuksel 'cd /Domains/speechy.frkn.com.tr/public_html/api && php migrate.php'
```

## Refund handling

Apple's `verifyReceipt` includes a `cancellation_date` field for refunded purchases. Our backend marks the receipt `is_valid = FALSE` when this field appears, and the next desktop-side verification fails. The user sees an "invalid receipt" alert and the app terminates.

## Why not subscription?

One-time purchase = simpler. No auto-renewal logic, no subscription state machine, no "user cancelled but is still in paid period" edge cases. Apple's `in_app[]` array contains a single permanent purchase record.

If subscriptions are added later, switch to the App Store Server API (JWT-based, replaces verifyReceipt) and add a subscription state column to `app_store_receipts`.
