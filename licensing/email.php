<?php

/**
 * OneSignal Email Service for Speechy
 *
 * Handles transactional email sending via OneSignal REST API.
 * Flow: register email as device → send email notification to that device.
 */

function onesignal_request(string $endpoint, array $payload): array
{
    $config = require __DIR__ . '/config.php';
    $onesignal = $config['onesignal'] ?? null;

    if (!$onesignal || empty($onesignal['app_id']) || empty($onesignal['api_key'])) {
        error_log('[Speechy Email] OneSignal not configured');
        return ['success' => false, 'error' => 'Email service not configured'];
    }

    $url = 'https://api.onesignal.com/' . ltrim($endpoint, '/');

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json; charset=utf-8',
            'Authorization: Key ' . $onesignal['api_key'],
        ],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 15,
    ]);

    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curl_error = curl_error($ch);
    curl_close($ch);

    if ($curl_error) {
        error_log("[Speechy Email] cURL error: $curl_error");
        return ['success' => false, 'error' => $curl_error];
    }

    $data = json_decode($response, true) ?? [];

    if ($http_code >= 400) {
        $err_msg = $data['errors'][0] ?? ($data['error'] ?? "HTTP $http_code");
        error_log("[Speechy Email] API error ($http_code): $err_msg — response: $response");
        return ['success' => false, 'error' => $err_msg, 'http_code' => $http_code];
    }

    return ['success' => true, 'data' => $data];
}

/**
 * Register an email address as a OneSignal device (email subscription).
 * Returns the player_id on success.
 */
function onesignal_register_email(string $email): ?string
{
    $config = require __DIR__ . '/config.php';

    $result = onesignal_request('api/v1/players', [
        'app_id' => $config['onesignal']['app_id'],
        'device_type' => 11, // email device
        'identifier' => $email,
        'tags' => [
            'source' => 'licensing',
            'registered_at' => date('Y-m-d'),
        ],
    ]);

    if (!$result['success']) {
        return null;
    }

    return $result['data']['id'] ?? null;
}

/**
 * Send an email via OneSignal to a specific email address.
 * Registers the email first if needed.
 */
function send_email(string $to_email, string $subject, string $html_body): bool
{
    $config = require __DIR__ . '/config.php';
    $onesignal = $config['onesignal'] ?? null;

    if (!$onesignal) {
        error_log('[Speechy Email] OneSignal not configured, skipping email');
        return false;
    }

    // Register email as device first
    $player_id = onesignal_register_email($to_email);

    if (!$player_id) {
        error_log("[Speechy Email] Failed to register email: $to_email");
        return false;
    }

    // Small delay to ensure device is registered
    usleep(300000); // 300ms

    $from_name = $onesignal['from_name'] ?? 'Speechy';
    $from_email = $onesignal['from_email'] ?? 'noreply@speechy.app';

    $result = onesignal_request('api/v1/notifications', [
        'app_id' => $onesignal['app_id'],
        'include_player_ids' => [$player_id],
        'email_subject' => $subject,
        'email_body' => $html_body,
        'email_from_name' => $from_name,
        'email_from_address' => $from_email,
    ]);

    if ($result['success']) {
        error_log("[Speechy Email] Sent '$subject' to $to_email");
        return true;
    }

    error_log("[Speechy Email] Failed to send '$subject' to $to_email");
    return false;
}

// ─── Email Templates ────────────────────────────────────────────────

function get_email_wrapper(string $content): string
{
    return '<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0; padding:0; background-color:#0f0b1a; font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#0f0b1a; padding:40px 20px;">
<tr><td align="center">
<table role="presentation" width="520" cellpadding="0" cellspacing="0" style="background-color:#1a1530; border:1px solid rgba(168,85,247,0.2); border-radius:16px; overflow:hidden;">

<!-- Header -->
<tr><td style="background:linear-gradient(135deg,#007AFF,#AF52DE); padding:32px 40px; text-align:center;">
  <div style="width:48px; height:48px; margin:0 auto 12px; background:rgba(255,255,255,0.2); border-radius:14px; line-height:48px; font-size:24px;">🎙</div>
  <div style="font-size:24px; font-weight:700; color:#ffffff; letter-spacing:-0.5px;">Speechy</div>
</td></tr>

<!-- Content -->
<tr><td style="padding:36px 40px;">
' . $content . '
</td></tr>

<!-- Footer -->
<tr><td style="padding:24px 40px; border-top:1px solid rgba(168,85,247,0.15); text-align:center;">
  <p style="margin:0; font-size:12px; color:#6b6580;">Privacy-First Voice Intelligence</p>
  <p style="margin:8px 0 0; font-size:11px; color:#4a4560;">macOS &amp; Windows &bull; 29 Languages &bull; 100% Local AI</p>
</td></tr>

</table>
</td></tr>
</table>
</body>
</html>';
}

function send_verification_email(string $email, string $verify_url): bool
{
    $content = '
  <h2 style="margin:0 0 16px; font-size:20px; font-weight:700; color:#f1f0f7;">Verify Your Email</h2>
  <p style="margin:0 0 24px; font-size:14px; color:#a8a3b8; line-height:1.6;">
    Welcome to Speechy! Click the button below to verify your email address and activate your free trial.
  </p>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center">
      <a href="' . htmlspecialchars($verify_url, ENT_QUOTES, 'UTF-8') . '"
         style="display:inline-block; padding:14px 36px; background:linear-gradient(135deg,#007AFF,#AF52DE);
                color:#ffffff; font-size:15px; font-weight:600; text-decoration:none;
                border-radius:10px; letter-spacing:0.3px;">
        Verify Email Address
      </a>
    </td></tr>
  </table>
  <p style="margin:24px 0 0; font-size:12px; color:#6b6580; line-height:1.6;">
    This link expires in 24 hours. If you didn\'t sign up for Speechy, you can safely ignore this email.
  </p>
  <p style="margin:16px 0 0; font-size:11px; color:#4a4560; word-break:break-all;">
    ' . htmlspecialchars($verify_url, ENT_QUOTES, 'UTF-8') . '
  </p>';

    $html = get_email_wrapper($content);
    return send_email($email, 'Verify your Speechy account', $html);
}

function send_license_email(string $email, string $license_key, string $license_type, ?string $expires_at): bool
{
    $type_label = [
        'trial' => '30-Day Free Trial',
        'monthly' => 'Monthly Subscription',
        'yearly' => 'Annual Subscription',
        'lifetime' => 'Lifetime License',
    ][$license_type] ?? ucfirst($license_type);

    $expiry_html = '';
    if ($expires_at) {
        $date = date('F j, Y', strtotime($expires_at));
        $expiry_html = '
    <tr>
      <td style="padding:8px 0; font-size:13px; color:#6b6580; border-bottom:1px solid rgba(168,85,247,0.1);">Expires</td>
      <td style="padding:8px 0; font-size:13px; color:#a8a3b8; text-align:right; border-bottom:1px solid rgba(168,85,247,0.1);">' . $date . '</td>
    </tr>';
    }

    $content = '
  <h2 style="margin:0 0 16px; font-size:20px; font-weight:700; color:#f1f0f7;">Your License Key</h2>
  <p style="margin:0 0 24px; font-size:14px; color:#a8a3b8; line-height:1.6;">
    Your Speechy license is ready! Copy the key below and paste it into the app to get started.
  </p>

  <!-- License Key Box -->
  <div style="background:rgba(79,140,255,0.1); border:1px solid rgba(79,140,255,0.3); border-radius:12px; padding:20px; text-align:center; margin-bottom:24px;">
    <p style="margin:0 0 8px; font-size:11px; color:#6b6580; text-transform:uppercase; letter-spacing:1px;">License Key</p>
    <code style="display:block; font-size:16px; color:#4f8cff; word-break:break-all; font-family:\'SF Mono\',Monaco,\'Courier New\',monospace; font-weight:600; letter-spacing:0.5px;">'
    . htmlspecialchars($license_key, ENT_QUOTES, 'UTF-8') .
    '</code>
  </div>

  <!-- License Details -->
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
    <tr>
      <td style="padding:8px 0; font-size:13px; color:#6b6580; border-bottom:1px solid rgba(168,85,247,0.1);">Plan</td>
      <td style="padding:8px 0; font-size:13px; color:#a8a3b8; text-align:right; border-bottom:1px solid rgba(168,85,247,0.1);">' . $type_label . '</td>
    </tr>
    ' . $expiry_html . '
    <tr>
      <td style="padding:8px 0; font-size:13px; color:#6b6580;">Platforms</td>
      <td style="padding:8px 0; font-size:13px; color:#a8a3b8; text-align:right;">macOS &amp; Windows</td>
    </tr>
  </table>

  <p style="margin:0; font-size:12px; color:#6b6580; line-height:1.6;">
    Open Speechy → enter your license key to activate. If you have any questions, reply to this email.
  </p>';

    $html = get_email_wrapper($content);
    return send_email($email, 'Your Speechy License Key', $html);
}

function send_welcome_email(string $email): bool
{
    $content = '
  <h2 style="margin:0 0 16px; font-size:20px; font-weight:700; color:#f1f0f7;">Welcome to Speechy! 🎉</h2>
  <p style="margin:0 0 20px; font-size:14px; color:#a8a3b8; line-height:1.6;">
    Your account is verified and your free trial is active. Here\'s how to get started:
  </p>

  <!-- Steps -->
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td style="padding:12px 0; border-bottom:1px solid rgba(168,85,247,0.1);">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="width:32px; height:32px; background:rgba(0,122,255,0.15); border-radius:8px; text-align:center; line-height:32px; font-size:14px; font-weight:700; color:#007AFF;">1</td>
        <td style="padding-left:14px;">
          <div style="font-size:13px; font-weight:600; color:#f1f0f7;">Download Speechy</div>
          <div style="font-size:12px; color:#6b6580; margin-top:2px;">Available for macOS. Windows coming soon.</div>
        </td>
      </tr></table>
    </td></tr>
    <tr><td style="padding:12px 0; border-bottom:1px solid rgba(168,85,247,0.1);">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="width:32px; height:32px; background:rgba(175,82,222,0.15); border-radius:8px; text-align:center; line-height:32px; font-size:14px; font-weight:700; color:#AF52DE;">2</td>
        <td style="padding-left:14px;">
          <div style="font-size:13px; font-weight:600; color:#f1f0f7;">Enter Your License Key</div>
          <div style="font-size:12px; color:#6b6580; margin-top:2px;">Check your previous email for the key.</div>
        </td>
      </tr></table>
    </td></tr>
    <tr><td style="padding:12px 0;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="width:32px; height:32px; background:rgba(63,185,80,0.15); border-radius:8px; text-align:center; line-height:32px; font-size:14px; font-weight:700; color:#3FB950;">3</td>
        <td style="padding-left:14px;">
          <div style="font-size:13px; font-weight:600; color:#f1f0f7;">Start Talking</div>
          <div style="font-size:12px; color:#6b6580; margin-top:2px;">Press your hotkey and speak — text appears instantly.</div>
        </td>
      </tr></table>
    </td></tr>
  </table>

  <div style="margin-top:24px; padding:16px; background:rgba(63,185,80,0.08); border:1px solid rgba(63,185,80,0.2); border-radius:10px;">
    <p style="margin:0; font-size:13px; color:#3FB950; font-weight:600;">Your Privacy Matters</p>
    <p style="margin:6px 0 0; font-size:12px; color:#a8a3b8; line-height:1.5;">All speech processing happens locally on your device. We never see or store your audio data.</p>
  </div>';

    $html = get_email_wrapper($content);
    return send_email($email, 'Welcome to Speechy!', $html);
}

function send_expiry_reminder_email(string $email, string $license_key, string $expires_at, int $days_left): bool
{
    $date = date('F j, Y', strtotime($expires_at));

    $urgency_color = $days_left <= 3 ? '#F85149' : ($days_left <= 7 ? '#F0883E' : '#58A6FF');

    $content = '
  <h2 style="margin:0 0 16px; font-size:20px; font-weight:700; color:#f1f0f7;">Your Trial Expires Soon</h2>
  <p style="margin:0 0 20px; font-size:14px; color:#a8a3b8; line-height:1.6;">
    Your Speechy trial has <strong style="color:' . $urgency_color . ';">' . $days_left . ' day' . ($days_left !== 1 ? 's' : '') . '</strong> remaining.
    Upgrade now to keep using all features without interruption.
  </p>

  <div style="background:rgba(79,140,255,0.08); border:1px solid rgba(79,140,255,0.2); border-radius:10px; padding:16px; margin-bottom:24px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td style="font-size:13px; color:#6b6580;">Current Plan</td>
        <td style="font-size:13px; color:#a8a3b8; text-align:right;">Free Trial</td>
      </tr>
      <tr>
        <td style="font-size:13px; color:#6b6580; padding-top:6px;">Expires</td>
        <td style="font-size:13px; color:' . $urgency_color . '; text-align:right; padding-top:6px; font-weight:600;">' . $date . '</td>
      </tr>
    </table>
  </div>

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center">
      <a href="https://speechy.app/pricing"
         style="display:inline-block; padding:14px 36px; background:linear-gradient(135deg,#007AFF,#AF52DE);
                color:#ffffff; font-size:15px; font-weight:600; text-decoration:none;
                border-radius:10px;">
        Upgrade Now
      </a>
    </td></tr>
  </table>

  <p style="margin:20px 0 0; font-size:12px; color:#6b6580; line-height:1.6; text-align:center;">
    Plans start at $9.99/month &bull; Lifetime option available
  </p>';

    $html = get_email_wrapper($content);
    return send_email($email, "Your Speechy trial expires in $days_left days", $html);
}
