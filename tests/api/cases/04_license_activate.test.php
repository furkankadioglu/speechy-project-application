<?php
/**
 * Test suite: POST /api/license/activate
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('04 — License Activate');

test('activate license on new device returns activated=true', function () {
    $lic = db_insert_license('yearly');
    $r   = http_post('/api/license/activate', [
        'license_key'  => $lic['license_key'],
        'machine_id'   => 'machine-001',
        'machine_label' => 'MacBook Pro',
        'app_platform' => 'macos',
        'app_version'  => '1.0.0',
    ]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['activated']);
    assert_eq('Device activated successfully', $r['body']['message']);
    assert_eq(1, db_count('activations'), 'activation row created');
});

test('activate same machine again is idempotent', function () {
    // Retrieve the license from previous test
    $lic = db_fetch_one("SELECT * FROM licenses WHERE license_type = 'yearly'");
    $r   = http_post('/api/license/activate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'machine-001',
    ]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['activated']);
    assert_eq('Device already activated', $r['body']['message']);
    assert_eq(1, db_count('activations'), 'still only one activation row');
});

test('second different machine with max_devices=1 returns 403', function () {
    $lic = db_fetch_one("SELECT * FROM licenses WHERE license_type = 'yearly'");
    $r   = http_post('/api/license/activate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'machine-002',
    ]);
    assert_status($r, 403);
    assert_true(str_contains($r['body']['error'], 'Device limit reached'), 'device limit message');
});

test('expired license activation returns 403', function () {
    $lic = db_insert_license('monthly', null, 1, 'active', date('c', strtotime('-1 day')));
    $r   = http_post('/api/license/activate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'machine-expired',
    ]);
    assert_status($r, 403);
    assert_true(str_contains($r['body']['error'], 'expired'), 'expired message');
});

test('non-existent license key returns 404', function () {
    $r = http_post('/api/license/activate', [
        'license_key' => 'no-such-key',
        'machine_id'  => 'machine-x',
    ]);
    assert_status($r, 404);
    assert_eq('Invalid license key', $r['body']['error']);
});

test('missing required fields returns 400', function () {
    $r = http_post('/api/license/activate', ['license_key' => 'only-key']);
    assert_status($r, 400);
    assert_eq('license_key and machine_id are required', $r['body']['error']);
});

test('invalid platform value returns 400', function () {
    $lic = db_insert_license('lifetime');
    $r   = http_post('/api/license/activate', [
        'license_key'  => $lic['license_key'],
        'machine_id'   => 'machine-plat',
        'app_platform' => 'linux',
    ]);
    assert_status($r, 400);
    assert_true(str_contains($r['body']['error'], 'app_platform'), 'platform error message');
});

test('windows platform is accepted', function () {
    $lic = db_insert_license('lifetime');
    $r   = http_post('/api/license/activate', [
        'license_key'  => $lic['license_key'],
        'machine_id'   => 'win-machine-001',
        'app_platform' => 'windows',
    ]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['activated']);
});

test('max_devices=2 allows two different machines', function () {
    $lic = db_insert_license('yearly', null, 2);
    $r1  = http_post('/api/license/activate', ['license_key' => $lic['license_key'], 'machine_id' => 'multi-A']);
    $r2  = http_post('/api/license/activate', ['license_key' => $lic['license_key'], 'machine_id' => 'multi-B']);
    assert_status($r1, 200);
    assert_status($r2, 200);
    $r3  = http_post('/api/license/activate', ['license_key' => $lic['license_key'], 'machine_id' => 'multi-C']);
    assert_status($r3, 403, 'third device blocked');
});
