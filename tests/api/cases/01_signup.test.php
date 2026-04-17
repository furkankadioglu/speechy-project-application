<?php
/**
 * Test suite: POST /api/signup
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('01 — Signup');

test('valid email creates a verification row (201)', function () {
    $r = http_post('/api/signup', ['email' => 'test.user+alpha@speechy-test.invalid']);
    assert_status($r, 201);
    assert_true(isset($r['body']['message']), 'message present');
    // Dev mode returns verify_url when email not sent
    assert_true(isset($r['body']['verify_url']), 'verify_url returned in dev mode');
    assert_eq(1, db_count('email_verifications'), 'one verification row created');
});

test('missing email returns 400', function () {
    $r = http_post('/api/signup', []);
    assert_status($r, 400);
    assert_eq('email is required', $r['body']['error']);
});

test('invalid email format returns 400', function () {
    $r = http_post('/api/signup', ['email' => 'not-an-email']);
    assert_status($r, 400);
    assert_eq('Invalid email format', $r['body']['error']);
});

test('another invalid email (@no-local) returns 400', function () {
    $r = http_post('/api/signup', ['email' => '@no-local.invalid']);
    assert_status($r, 400);
    assert_eq('Invalid email format', $r['body']['error']);
});

test('duplicate pending request coalesces (200 not 201)', function () {
    // Already has a pending verification from first test
    $r = http_post('/api/signup', ['email' => 'test.user+alpha@speechy-test.invalid']);
    assert_status($r, 200);
    assert_true(str_contains($r['body']['message'], 'already sent'), 'coalesce message');
    // No new row created
    assert_eq(1, db_count('email_verifications'), 'still only one row');
});

test('existing trial license for email returns 409', function () {
    db_insert_license('trial', 'collision@speechy-test.invalid');
    $r = http_post('/api/signup', ['email' => 'collision@speechy-test.invalid']);
    assert_status($r, 409);
    assert_true(str_contains($r['body']['error'], 'trial license'), 'trial exists error');
});

test('invalid JSON body returns 400', function () {
    $ch = curl_init(API_BASE_URL . '/api/signup');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => '{invalid json',
        CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
        CURLOPT_TIMEOUT        => 10,
    ]);
    $raw    = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    @curl_close($ch);
    assert_eq(400, $status, 'bad JSON -> 400');
});

test('oversized body (>64KB) returns 413', function () {
    $big = json_encode(['email' => str_repeat('a', 70000)]);
    $ch  = curl_init(API_BASE_URL . '/api/signup');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $big,
        CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
        CURLOPT_TIMEOUT        => 10,
    ]);
    $raw    = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    @curl_close($ch);
    assert_eq(413, $status, 'oversized body -> 413');
});

test('rate limit — 5 rows for same IP inserted directly, 6th request returns 429', function () {
    // The dev server always uses REMOTE_ADDR=127.0.0.1.
    // Rate-limit logic counts rows in email_verifications WHERE ip_address = :ip.
    // We insert 5 rows directly with ip=127.0.0.1 and a created_at within the last hour.
    $pdo = harness_db();
    for ($i = 0; $i < 5; $i++) {
        $pdo->exec("
            INSERT INTO email_verifications (email, token, expires_at, ip_address)
            VALUES ('rate_limit_{$i}@speechy-test.invalid', '" . bin2hex(random_bytes(32)) . "', NOW() + INTERVAL '24 hours', '127.0.0.1')
        ");
    }
    // The existing pending row for alpha was already in there (from test 1, ip=127.0.0.1)
    // but let's use a fresh email to trigger a real insert attempt
    $r = http_post('/api/signup', ['email' => 'ratelimited@speechy-test.invalid']);
    assert_status($r, 429, 'rate limit hit -> 429');
    assert_true(str_contains($r['body']['error'], 'Too many requests'), 'rate limit message');
});
