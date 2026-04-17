<?php
/**
 * Test suite: POST /api/license/verify
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('03 — License Verify');

test('active license returns valid=true', function () {
    $lic = db_insert_license('yearly');
    $r   = http_post('/api/license/verify', ['license_key' => $lic['license_key']]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['valid']);
    assert_eq('active', $r['body']['license']['status']);
    assert_eq('yearly', $r['body']['license']['license_type']);
    assert_true(isset($r['body']['license']['max_devices']), 'max_devices present');
});

test('expired license is auto-expired and returns valid=false', function () {
    // Insert with past expiry
    $lic = db_insert_license('monthly', null, 1, 'active', date('c', strtotime('-1 day')));
    $r   = http_post('/api/license/verify', ['license_key' => $lic['license_key']]);
    assert_status($r, 200);
    assert_eq(false, $r['body']['valid']);
    assert_eq('expired', $r['body']['license']['status']);
    // Verify DB was updated
    $row = db_fetch_one('SELECT status FROM licenses WHERE id = :id', ['id' => $lic['id']]);
    assert_eq('expired', $row['status'], 'DB updated to expired');
});

test('revoked license returns valid=false', function () {
    $lic = db_insert_license('lifetime', null, 1, 'revoked');
    $r   = http_post('/api/license/verify', ['license_key' => $lic['license_key']]);
    assert_status($r, 200);
    assert_eq(false, $r['body']['valid']);
    assert_eq('revoked', $r['body']['license']['status']);
});

test('suspended license returns valid=false', function () {
    $lic = db_insert_license('lifetime', null, 1, 'suspended');
    $r   = http_post('/api/license/verify', ['license_key' => $lic['license_key']]);
    assert_status($r, 200);
    assert_eq(false, $r['body']['valid']);
    assert_eq('suspended', $r['body']['license']['status']);
});

test('invalid license key returns 404', function () {
    $r = http_post('/api/license/verify', ['license_key' => 'definitely-not-a-real-key']);
    assert_status($r, 404);
    assert_eq('Invalid license key', $r['body']['error']);
});

test('missing license_key field returns 400', function () {
    $r = http_post('/api/license/verify', []);
    assert_status($r, 400);
    assert_eq('license_key is required', $r['body']['error']);
});

test('lifetime license never expires', function () {
    $lic = db_insert_license('lifetime', null, 1, 'active', null);
    $r   = http_post('/api/license/verify', ['license_key' => $lic['license_key']]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['valid']);
    assert_eq('active', $r['body']['license']['status']);
});
