<?php
/**
 * Test suite: GET /api/version/check
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('07 — Version Check');

test('GET /api/version/check?platform=macos returns version info', function () {
    $r = http_get('/api/version/check?platform=macos');
    assert_status($r, 200);
    assert_eq('macos', $r['body']['platform']);
    assert_true(isset($r['body']['latest_version']), 'latest_version present');
    assert_true(isset($r['body']['minimum_version']), 'minimum_version present');
    assert_true(isset($r['body']['update_url']), 'update_url present');
    // Versions are seeded by migration 005 — should be semver-like
    assert_true(preg_match('/^\d+\.\d+\.\d+$/', $r['body']['latest_version']) === 1, 'latest_version semver');
    assert_true(preg_match('/^\d+\.\d+\.\d+$/', $r['body']['minimum_version']) === 1, 'minimum_version semver');
});

test('GET /api/version/check?platform=windows returns version info', function () {
    $r = http_get('/api/version/check?platform=windows');
    assert_status($r, 200);
    assert_eq('windows', $r['body']['platform']);
    assert_true(isset($r['body']['latest_version']), 'latest_version present');
});

test('GET /api/version/check?platform=ios returns version info', function () {
    $r = http_get('/api/version/check?platform=ios');
    assert_status($r, 200);
    assert_eq('ios', $r['body']['platform']);
});

test('unknown platform returns 400', function () {
    $r = http_get('/api/version/check?platform=android');
    assert_status($r, 400);
    assert_true(isset($r['body']['error']), 'error present');
});

test('missing platform parameter returns 400', function () {
    $r = http_get('/api/version/check');
    assert_status($r, 400);
    assert_true(isset($r['body']['error']), 'error present');
});

test('admin can update macos version and it is reflected in version check', function () {
    $r_update = http_put('/api/admin/version', [
        'platform'        => 'macos',
        'latest_version'  => '2.5.0',
        'minimum_version' => '1.5.0',
        'update_url'      => 'https://speechy.frkn.com.tr/download',
        'notes'           => 'Bug fixes',
    ], admin_headers());
    assert_status($r_update, 200);
    assert_eq(true, $r_update['body']['updated']);
    assert_eq('2.5.0', $r_update['body']['version']['latest_version']);

    $r = http_get('/api/version/check?platform=macos');
    assert_status($r, 200);
    assert_eq('2.5.0', $r['body']['latest_version'], 'updated version reflected');
    assert_eq('1.5.0', $r['body']['minimum_version'], 'updated minimum version reflected');
});

test('admin can list all platform versions', function () {
    $r = http_get('/api/admin/version', admin_headers());
    assert_status($r, 200);
    assert_true(isset($r['body']['versions']), 'versions key');
    assert_true(count($r['body']['versions']) >= 3, 'at least 3 platforms');
    $platforms = array_column($r['body']['versions'], 'platform');
    assert_true(in_array('macos', $platforms), 'macos in list');
    assert_true(in_array('windows', $platforms), 'windows in list');
    assert_true(in_array('ios', $platforms), 'ios in list');
});
