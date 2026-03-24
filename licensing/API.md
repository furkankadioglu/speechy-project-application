# Speechy Licensing API

Base URL: `https://licensing.speechy.app` (production) or `http://localhost:8000` (dev)

## Authentication

Admin endpoints require an API key via the `X-API-Key` header.
App-facing and signup endpoints use the license key as the credential — no header auth needed.

---

## Signup & Email Verification

### POST /api/signup

Register an email for a 30-day free trial. Sends a verification link to the email.

**Request:**
```json
{
  "email": "user@example.com"
}
```

**Success (201):**
```json
{
  "message": "Verification email sent. Please check your inbox.",
  "verify_url": "https://licensing.speechy.app/api/verify-email?token=abc123..."
}
```

**Errors:**
| Status | Error |
|--------|-------|
| 400 | `email is required` |
| 400 | `Invalid email format` |
| 409 | `A trial license already exists for this email` |

---

### GET /api/verify-email?token={token}

Verify an email address and activate the 30-day trial license.
Returns an HTML page with the license key on success.

**Parameters:**
| Name | In | Description |
|------|----|-------------|
| token | query | 64-char hex verification token |

**Success:** HTML page showing the license key.
**Failure:** HTML page with error message (expired, already used, invalid).

---

## App-Facing Endpoints

### POST /api/license/verify

Check whether a license key is valid. Automatically expires licenses past their `expires_at` date.

**Request:**
```json
{
  "license_key": "abc123..."
}
```

**Success (200):**
```json
{
  "valid": true,
  "license": {
    "license_type": "yearly",
    "status": "active",
    "expires_at": "2027-02-16T12:00:00+00:00",
    "max_devices": 1
  }
}
```

**Errors:**
| Status | Error |
|--------|-------|
| 400 | `license_key is required` |
| 404 | `Invalid license key` |

---

### POST /api/license/activate

Bind a license to a device. Enforces the `max_devices` limit.

**Request:**
```json
{
  "license_key": "abc123...",
  "machine_id": "hardware-uuid",
  "machine_label": "MacBook Pro 14-inch",
  "app_platform": "macos",
  "app_version": "1.2.0"
}
```

Required fields: `license_key`, `machine_id`
Optional fields: `machine_label`, `app_platform` (`macos` | `ios`), `app_version`

**Success (200):**
```json
{
  "activated": true,
  "message": "Device activated successfully"
}
```

**Already activated (200):**
```json
{
  "activated": true,
  "message": "Device already activated"
}
```

**Errors:**
| Status | Error |
|--------|-------|
| 400 | `license_key and machine_id are required` |
| 400 | `app_platform must be macos or ios` |
| 403 | `License is expired` |
| 403 | `Device limit reached (1). Deactivate another device first.` |
| 404 | `Invalid license key` |

---

### POST /api/license/deactivate

Unbind a device from a license. Allows transferring the license to another machine.

**Request:**
```json
{
  "license_key": "abc123...",
  "machine_id": "hardware-uuid"
}
```

**Success (200):**
```json
{
  "deactivated": true,
  "message": "Device deactivated successfully"
}
```

**Errors:**
| Status | Error |
|--------|-------|
| 400 | `license_key and machine_id are required` |
| 404 | `Invalid license key` |
| 404 | `No active activation found for this device` |

---

## Admin Endpoints

All admin endpoints require the `X-API-Key` header.

### GET /api/admin/licenses

List licenses with pagination and filters.

**Query Parameters:**
| Name | Description | Default |
|------|-------------|---------|
| page | Page number | 1 |
| per_page | Results per page (1-100) | 20 |
| status | Filter: `active`, `expired`, `revoked`, `suspended` | — |
| license_type | Filter: `trial`, `monthly`, `yearly`, `lifetime` | — |
| email | Search by email (partial match) | — |

**Success (200):**
```json
{
  "licenses": [ ... ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 42,
    "total_pages": 3
  }
}
```

---

### GET /api/admin/licenses/{id}

Get a single license with its full activation history.

**Success (200):**
```json
{
  "license": { ... },
  "activations": [ ... ]
}
```

---

### POST /api/admin/licenses

Create a new license.

**Request:**
```json
{
  "license_type": "yearly",
  "owner_email": "user@example.com",
  "owner_name": "John Doe",
  "notes": "Purchased via website",
  "max_devices": 2
}
```

Required: `license_type` (`monthly` | `yearly` | `lifetime`)
Optional: `owner_email`, `owner_name`, `notes`, `max_devices` (1-100, default 1)

**Success (201):**
```json
{
  "license": {
    "id": 1,
    "license_key": "abc123...",
    "license_type": "yearly",
    "status": "active",
    "expires_at": "2027-02-16T12:00:00+00:00",
    ...
  }
}
```

---

### POST /api/admin/licenses/trial

Create a trial license (1 per email).

**Request:**
```json
{
  "owner_email": "user@example.com",
  "owner_name": "John Doe"
}
```

Required: `owner_email`

**Success (201):** Same as above.

**Errors:**
| Status | Error |
|--------|-------|
| 409 | `A trial license already exists for this email` |

---

### PUT /api/admin/licenses/{id}

Update license fields.

**Request (all fields optional):**
```json
{
  "status": "suspended",
  "owner_email": "new@example.com",
  "owner_name": "Jane Doe",
  "notes": "Updated note",
  "expires_at": "2028-01-01T00:00:00+00:00",
  "max_devices": 3
}
```

**Success (200):**
```json
{
  "license": { ... }
}
```

---

### DELETE /api/admin/licenses/{id}

Revoke a license (soft-delete — sets status to `revoked`).

**Success (200):**
```json
{
  "revoked": true,
  "license": { ... }
}
```

---

## License Types & Expiry

| Type | Duration | Limit |
|------|----------|-------|
| trial | 30 days (via email signup) or configurable (via admin) | 1 per email |
| monthly | 30 days from creation | — |
| yearly | 365 days from creation | — |
| lifetime | Never expires | — |

## Error Format

All errors return JSON:
```json
{
  "error": "Error message here"
}
```

## Setup

```bash
# 1. Create database
createdb speechy_licensing

# 2. Configure
cp config.example.php config.php
# Edit config.php with your credentials

# 3. Run migrations
php migrate.php

# 4. Start dev server
php -S localhost:8000 index.php
```
