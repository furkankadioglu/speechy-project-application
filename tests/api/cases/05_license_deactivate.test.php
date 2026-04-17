<?php
/**
 * Test suite: POST /api/license/deactivate
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('05 — License Deactivate');

test('deactivate an active machine returns deactivated=true', function () {
    $lic = db_insert_license('yearly');
    // Activate first
    http_post('/api/license/activate', ['license_key' => $lic['license_key'], 'machine_id' => 'deact-m1']);

    $r = http_post('/api/license/deactivate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'deact-m1',
    ]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['deactivated']);
    assert_eq('Device deactivated successfully', $r['body']['message']);

    // Activation row should now have is_active=false
    $row = db_fetch_one('SELECT is_active FROM activations WHERE machine_id = :m', ['m' => 'deact-m1']);
    // PDO returns booleans as PHP bool or as '0'/'1' depending on driver — treat all falsy as false
    assert_true($row !== null, 'activation row found');
    assert_true(!$row['is_active'], 'is_active set to false');
});

test('re-activation on new machine works after deactivate', function () {
    $lic = db_fetch_one("SELECT * FROM licenses WHERE license_type = 'yearly'");
    $r   = http_post('/api/license/activate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'deact-m2',
    ]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['activated']);
});

test('deactivate non-existent activation returns 404', function () {
    $lic = db_insert_license('lifetime');
    $r   = http_post('/api/license/deactivate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'ghost-machine',
    ]);
    assert_status($r, 404);
    assert_eq('No active activation found for this device', $r['body']['error']);
});

test('deactivate with non-existent license key returns 404', function () {
    $r = http_post('/api/license/deactivate', [
        'license_key' => 'no-such-key',
        'machine_id'  => 'some-machine',
    ]);
    assert_status($r, 404);
    assert_eq('Invalid license key', $r['body']['error']);
});

test('missing fields returns 400', function () {
    $r = http_post('/api/license/deactivate', ['license_key' => 'only-key-no-machine']);
    assert_status($r, 400);
    assert_eq('license_key and machine_id are required', $r['body']['error']);
});

test('deactivating already-deactivated machine returns 404', function () {
    // machine deact-m1 was already deactivated above
    $lic = db_fetch_one("SELECT * FROM licenses WHERE license_type = 'yearly'");
    $r   = http_post('/api/license/deactivate', [
        'license_key' => $lic['license_key'],
        'machine_id'  => 'deact-m1',
    ]);
    assert_status($r, 404, 'double deactivate returns 404');
});
