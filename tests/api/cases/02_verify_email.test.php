<?php
/**
 * Test suite: GET /api/verify-email
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('02 — Verify Email');

// Helper: insert a verification token, optionally expired/used
function insert_verification(string $email, bool $expired = false, bool $used = false): string {
    $pdo     = harness_db();
    $token   = bin2hex(random_bytes(32));
    $exp     = $expired ? date('c', strtotime('-1 hour')) : date('c', strtotime('+24 hours'));
    $verified = $used ? 'NOW()' : 'NULL';
    $pdo->exec("
        INSERT INTO email_verifications (email, token, expires_at, verified_at, ip_address)
        VALUES ('{$email}', '{$token}', '{$exp}', {$verified}, '10.0.0.1')
    ");
    return $token;
}

test('valid token returns HTML success page and license_key in HTML', function () {
    $token = insert_verification('test.user+alpha@speechy-test.invalid');
    $r     = http_get('/api/verify-email?token=' . $token);
    assert_eq(200, $r['status']);
    $html = is_string($r['body']) ? $r['body'] : '';
    assert_true(str_contains($html, 'Welcome to Speechy') || str_contains($html, 'verified'), 'success HTML');
    assert_true(str_contains($html, 'License Key') || str_contains($html, 'license'), 'license key in HTML');
});

test('valid token creates a trial license in DB', function () {
    assert_eq(1, db_count('licenses'), 'one trial license created after verify');
    $lic = db_fetch_one("SELECT * FROM licenses WHERE license_type = 'trial'");
    assert_true($lic !== null, 'trial license row exists');
    assert_eq('active', $lic['status']);
    assert_true($lic['expires_at'] !== null, 'expires_at set');
    // expiry should be ~30 days from now
    $exp = strtotime($lic['expires_at']);
    assert_true($exp > time() + 25 * 86400, '30-day expiry roughly correct');
});

test('already-used token returns 400 HTML failure', function () {
    // The token used in previous test is now marked verified
    $row = db_fetch_one("SELECT token FROM email_verifications WHERE verified_at IS NOT NULL");
    assert_true($row !== null, 'used token row exists');
    $r = http_get('/api/verify-email?token=' . $row['token']);
    assert_eq(400, $r['status']);
    $html = is_string($r['body']) ? $r['body'] : '';
    assert_true(str_contains($html, 'already been verified'), 'already used message');
});

test('expired token returns 400 HTML failure', function () {
    $token = insert_verification('expired@speechy-test.invalid', true);
    $r     = http_get('/api/verify-email?token=' . $token);
    assert_eq(400, $r['status']);
    $html = is_string($r['body']) ? $r['body'] : '';
    assert_true(str_contains($html, 'expired'), 'expired message');
});

test('non-existent token returns 400 HTML failure', function () {
    $r = http_get('/api/verify-email?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    assert_eq(400, $r['status']);
});

test('missing token returns 400', function () {
    $r = http_get('/api/verify-email');
    assert_eq(400, $r['status']);
});

test('verify-email returns the license_key in HTML', function () {
    // Use a fresh email+token
    $token = insert_verification('fresh@speechy-test.invalid');
    $r     = http_get('/api/verify-email?token=' . $token);
    assert_eq(200, $r['status']);
    $html  = is_string($r['body']) ? $r['body'] : '';
    // The license key is a 48-char hex string
    assert_true(preg_match('/[0-9a-f]{48}/', $html) === 1, 'license key hex present in HTML');
});
