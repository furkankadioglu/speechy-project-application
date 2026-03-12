# License Integration - Desktop App

## Overview
The desktop app now requires a valid license to function. Without a license, only the license activation screen is shown.

## How It Works

### Startup Flow
1. App starts → splash screen
2. After splash → check `LicenseManager.shared.isLicensed`
3. If licensed → `initializeFullApp()` (hotkeys, recorder, whisper, etc.)
4. If not licensed → `showLicenseScreen()` (license key input UI)
5. After activation → transitions to full app

### LicenseManager
- Stores license key in `UserDefaults` (`speechy_license_key`)
- Uses hardware UUID (`IOPlatformUUID`) as machine identifier
- Caches license status for offline startup
- Re-verifies license every 24 hours in background

### API Integration
- `POST /api/license/verify` — checks if license key is valid
- `POST /api/license/activate` — registers this machine (sends machine_id, machine_label, platform)
- `POST /api/license/deactivate` — unregisters machine (for license transfer)

### LicenseView
- Clean UI matching Speechy brand (blue→purple gradient)
- License key text field with monospace font
- Error/success messages
- Link to speechy.frkn.com.tr for getting a trial

### Security
- License verified server-side on activation
- Background re-verification prevents expired licenses from working
- Device limit enforced server-side (max_devices per license)
- Machine ID is hardware-based, not spoofable
