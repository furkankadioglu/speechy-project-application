# Email System (OneSignal Integration)

## Overview
Transactional email system integrated into the PHP licensing backend using OneSignal's REST API.

## Architecture
- **Provider:** OneSignal (email channel)
- **Integration:** `licensing/email.php` — standalone helper, no external PHP dependencies
- **Transport:** OneSignal REST API v1 (`/api/v1/players` + `/api/v1/notifications`)
- **Flow:** Register email as OneSignal device (type 11) → Send email notification to that device

## Configuration
OneSignal credentials are stored in `licensing/config.php` (gitignored):
```php
'onesignal' => [
    'app_id' => '...',
    'api_key' => 'os_v2_app_...',
    'from_name' => 'Speechy',
    'from_email' => 'noreply@speechy.app',
],
```

## Email Templates (4 types)

### 1. Verification Email (`send_verification_email`)
- **Trigger:** `POST /api/signup`
- **Content:** "Verify Your Email" with CTA button linking to verify URL
- **Expiry note:** 24 hours

### 2. License Key Email (`send_license_email`)
- **Trigger:** After email verification succeeds, or when admin creates a license with email
- **Content:** License key in a styled box, plan type, expiration date, platform info

### 3. Welcome Email (`send_welcome_email`)
- **Trigger:** After email verification succeeds (sent right after license email)
- **Content:** 3-step getting started guide, privacy assurance

### 4. Expiry Reminder Email (`send_expiry_reminder_email`)
- **Trigger:** Not yet automated (available as function for future cron job)
- **Content:** Days remaining with urgency color coding, upgrade CTA
- **Color coding:** Blue (>7 days), Orange (3-7 days), Red (≤3 days)

## Graceful Degradation
If OneSignal is not configured or email sending fails:
- Signup still works — returns `verify_url` in API response (dev fallback)
- Verification page still shows license key
- Errors are logged via `error_log()`, never exposed to user

## Files Changed
- `licensing/email.php` — New: Email helper with OneSignal integration + 4 HTML templates
- `licensing/index.php` — Added `require email.php`
- `licensing/config.example.php` — Added `onesignal` config block
- `licensing/routes/signup.php` — Integrated verification + license + welcome emails
- `licensing/routes/admin.php` — Sends license email when admin creates license with email
- `licensing/routes/app.php` — Added `windows` to valid platforms
