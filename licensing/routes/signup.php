<?php

function handle_signup_route(string $method, string $path): bool
{
    if ($method === 'POST' && $path === '/api/signup') {
        handle_signup();
        return true;
    }

    if ($method === 'GET' && $path === '/api/verify-email') {
        handle_verify_email();
        return true;
    }

    return false;
}

function handle_signup(): void
{
    // Rate limit: max 5 signups per IP per hour
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $pdo = get_db();

    $stmt = $pdo->prepare(
        "SELECT COUNT(*) FROM email_verifications WHERE created_at > NOW() - INTERVAL '1 hour' AND ip_address = :ip"
    );
    $stmt->execute(['ip' => $ip]);
    $recent_count = (int) $stmt->fetchColumn();

    if ($recent_count >= 5) {
        json_error('Too many requests. Please try again later.', 429);
    }

    $body = get_json_body();
    $email = sanitize_string($body['email'] ?? '', 255);

    if ($email === '') {
        json_error('email is required');
    }

    if (!validate_email($email)) {
        json_error('Invalid email format');
    }

    $email = strtolower($email);

    // Check if a trial license already exists for this email
    $stmt = $pdo->prepare(
        'SELECT id FROM licenses WHERE owner_email = :email AND license_type = :type'
    );
    $stmt->execute(['email' => $email, 'type' => 'trial']);

    if ($stmt->fetch()) {
        json_error('A trial license already exists for this email', 409);
    }

    // Check if there's a pending (unverified, unexpired) verification
    $stmt = $pdo->prepare(
        'SELECT id FROM email_verifications WHERE email = :email AND verified_at IS NULL AND expires_at > NOW()'
    );
    $stmt->execute(['email' => $email]);

    if ($stmt->fetch()) {
        // Resend scenario — just confirm without creating a new token
        json_response([
            'message' => 'Verification email already sent. Please check your inbox.',
        ]);
        return;
    }

    // Create verification token
    $token = bin2hex(random_bytes(32));
    $expires_at = date('c', strtotime('+24 hours'));

    $stmt = $pdo->prepare('
        INSERT INTO email_verifications (email, token, expires_at, ip_address)
        VALUES (:email, :token, :expires_at, :ip)
    ');
    $stmt->execute([
        'email' => $email,
        'token' => $token,
        'expires_at' => $expires_at,
        'ip' => $ip,
    ]);

    $config = require __DIR__ . '/../config.php';
    $base_url = $config['base_url'] ?? 'http://localhost:8000';
    $verify_url = $base_url . '/api/verify-email?token=' . $token;

    // Send verification email via OneSignal
    $email_sent = send_verification_email($email, $verify_url);

    $response = [
        'message' => 'Verification email sent. Please check your inbox.',
    ];

    // Include verify_url in dev mode (no OneSignal configured or send failed)
    if (!$email_sent) {
        $response['verify_url'] = $verify_url;
    }

    json_response($response, 201);
}

function handle_verify_email(): void
{
    $token = sanitize_string($_GET['token'] ?? '', 64);

    if ($token === '') {
        send_verification_html('Invalid verification link.', false);
        return;
    }

    $pdo = get_db();

    // Find the verification record
    $stmt = $pdo->prepare(
        'SELECT * FROM email_verifications WHERE token = :token'
    );
    $stmt->execute(['token' => $token]);
    $verification = $stmt->fetch();

    if (!$verification) {
        send_verification_html('Invalid verification link.', false);
        return;
    }

    if ($verification['verified_at'] !== null) {
        send_verification_html('This email has already been verified.', false);
        return;
    }

    if (strtotime($verification['expires_at']) < time()) {
        send_verification_html('This verification link has expired. Please sign up again.', false);
        return;
    }

    $email = $verification['email'];

    // Start transaction for atomic trial creation
    $pdo->beginTransaction();

    try {
        // Check for existing trial (race condition protection)
        $check = $pdo->prepare(
            'SELECT id FROM licenses WHERE owner_email = :email AND license_type = :type FOR UPDATE'
        );
        $check->execute(['email' => $email, 'type' => 'trial']);

        if ($check->fetch()) {
            $pdo->rollBack();
            send_verification_html('A trial license already exists for this email.', false);
            return;
        }

        // Create 30-day trial license
        $license_key = generate_license_key();
        $expires_at = date('c', strtotime('+30 days'));

        $stmt = $pdo->prepare('
            INSERT INTO licenses (license_key, license_type, owner_email, expires_at)
            VALUES (:key, :type, :email, :expires)
            RETURNING id, license_key
        ');
        $stmt->execute([
            'key' => $license_key,
            'type' => 'trial',
            'email' => $email,
            'expires' => $expires_at,
        ]);

        $license = $stmt->fetch();

        // Mark verification as completed
        $stmt = $pdo->prepare('
            UPDATE email_verifications
            SET verified_at = NOW(), license_id = :lid
            WHERE id = :id
        ');
        $stmt->execute([
            'lid' => $license['id'],
            'id' => $verification['id'],
        ]);

        $pdo->commit();
    } catch (PDOException $e) {
        $pdo->rollBack();
        send_verification_html('Something went wrong. Please try again.', false);
        return;
    }

    // Send license key and welcome emails (non-blocking — don't fail verification if email fails)
    $config = require __DIR__ . '/../config.php';
    $trial_days = $config['trial_duration_days'] ?? 30;
    $expires_at = date('c', strtotime("+{$trial_days} days"));

    send_license_email($email, $license['license_key'], 'trial', $expires_at);
    send_welcome_email($email);

    send_verification_html(
        'Your email has been verified! Your 30-day free trial is now active.',
        true,
        $license['license_key']
    );
}

function send_verification_html(string $message, bool $success, string $license_key = ''): void
{
    http_response_code($success ? 200 : 400);
    header('Content-Type: text/html; charset=utf-8');

    $icon = $success ? '&#10003;' : '&#10007;';
    $color = $success ? '#22c55e' : '#ef4444';
    $bg_color = $success ? 'rgba(34, 197, 94, 0.1)' : 'rgba(239, 68, 68, 0.1)';

    $license_html = '';
    if ($license_key !== '') {
        $license_html = '
            <div style="margin-top: 24px; padding: 20px; background: rgba(79, 140, 255, 0.1); border: 1px solid rgba(79, 140, 255, 0.3); border-radius: 12px;">
                <p style="font-size: 0.85rem; color: #a8a3b8; margin-bottom: 8px;">Your License Key</p>
                <code style="display: block; font-size: 1rem; color: #4f8cff; word-break: break-all; font-family: monospace;">' . htmlspecialchars($license_key, ENT_QUOTES, 'UTF-8') . '</code>
                <p style="font-size: 0.8rem; color: #6b6580; margin-top: 12px;">Copy this key and paste it into the Speechy app to activate your trial.</p>
            </div>';
    }

    echo '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Speechy — Email Verification</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0f0b1a;
            color: #f1f0f7;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 24px;
        }
        .card {
            max-width: 480px;
            width: 100%;
            background: #1a1530;
            border: 1px solid rgba(168, 85, 247, 0.2);
            border-radius: 20px;
            padding: 48px 36px;
            text-align: center;
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.3);
        }
    </style>
</head>
<body>
    <div class="card">
        <div style="width: 64px; height: 64px; margin: 0 auto 20px; border-radius: 50%; background: ' . $bg_color . '; display: flex; align-items: center; justify-content: center; font-size: 28px; color: ' . $color . ';">' . $icon . '</div>
        <h1 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 12px;">' . ($success ? 'Welcome to Speechy!' : 'Verification Failed') . '</h1>
        <p style="color: #a8a3b8; line-height: 1.6;">' . htmlspecialchars($message, ENT_QUOTES, 'UTF-8') . '</p>
        ' . $license_html . '
    </div>
</body>
</html>';
    exit;
}
