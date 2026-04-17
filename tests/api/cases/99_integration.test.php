<?php
/**
 * Test suite: End-to-end integration flows
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('99 — Integration Flows');

// ─── Flow 1: Full trial lifecycle ─────────────────────────────────────────

test('[Trial Flow] signup creates verification row', function () {
    $r = http_post('/api/signup', ['email' => 'trial.flow@speechy-test.invalid']);
    assert_status($r, 201);
    assert_true(isset($r['body']['verify_url']), 'verify_url returned');

    // Store token for next step
    $GLOBALS['trial_flow_verify_url'] = $r['body']['verify_url'];
});

test('[Trial Flow] verify-email activates trial and returns HTML with license key', function () {
    $url   = $GLOBALS['trial_flow_verify_url'] ?? null;
    assert_true($url !== null, 'verify_url from previous step');

    $path  = parse_url($url, PHP_URL_PATH) . '?' . parse_url($url, PHP_URL_QUERY);
    $r     = http_get($path);
    assert_eq(200, $r['status']);

    $html  = is_string($r['body']) ? $r['body'] : '';
    assert_true(preg_match('/[0-9a-f]{48}/', $html, $m) === 1, 'license key in HTML');
    $GLOBALS['trial_license_key'] = $m[0];
});

test('[Trial Flow] license verify returns valid=true for trial', function () {
    $key = $GLOBALS['trial_license_key'] ?? null;
    assert_true($key !== null, 'trial license key present');

    $r = http_post('/api/license/verify', ['license_key' => $key]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['valid']);
    assert_eq('trial', $r['body']['license']['license_type']);
});

test('[Trial Flow] activate on machine A succeeds', function () {
    $key = $GLOBALS['trial_license_key'];
    $r   = http_post('/api/license/activate', [
        'license_key' => $key,
        'machine_id'  => 'trial-machine-A',
        'app_platform' => 'macos',
    ]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['activated']);
});

test('[Trial Flow] activate on machine B fails (max_devices=1)', function () {
    $key = $GLOBALS['trial_license_key'];
    $r   = http_post('/api/license/activate', [
        'license_key' => $key,
        'machine_id'  => 'trial-machine-B',
    ]);
    assert_status($r, 403);
    assert_true(str_contains($r['body']['error'], 'Device limit reached'), 'device limit hit');
});

test('[Trial Flow] deactivate machine A then machine B succeeds', function () {
    $key = $GLOBALS['trial_license_key'];
    $r1  = http_post('/api/license/deactivate', ['license_key' => $key, 'machine_id' => 'trial-machine-A']);
    assert_status($r1, 200);

    $r2  = http_post('/api/license/activate', ['license_key' => $key, 'machine_id' => 'trial-machine-B']);
    assert_status($r2, 200);
    assert_eq(true, $r2['body']['activated']);
});

// ─── Flow 2: Admin manages a yearly license ────────────────────────────────

test('[Admin Flow] create yearly license with max_devices=2', function () {
    $r = http_post('/api/admin/licenses', [
        'license_type' => 'yearly',
        'owner_email'  => 'managed@speechy-test.invalid',
        'max_devices'  => 2,
    ], admin_headers());
    assert_status($r, 201);
    $GLOBALS['admin_lic'] = $r['body']['license'];
});

test('[Admin Flow] client can verify the created license', function () {
    $lic = $GLOBALS['admin_lic'];
    $r   = http_post('/api/license/verify', ['license_key' => $lic['license_key']]);
    assert_status($r, 200);
    assert_eq(true, $r['body']['valid']);
});

test('[Admin Flow] activate 2 devices succeeds', function () {
    $key = $GLOBALS['admin_lic']['license_key'];
    $r1  = http_post('/api/license/activate', ['license_key' => $key, 'machine_id' => 'adm-m1']);
    $r2  = http_post('/api/license/activate', ['license_key' => $key, 'machine_id' => 'adm-m2']);
    assert_status($r1, 200);
    assert_status($r2, 200);
});

test('[Admin Flow] admin reduces max_devices to 1, third activate fails', function () {
    $id  = $GLOBALS['admin_lic']['id'];
    $key = $GLOBALS['admin_lic']['license_key'];

    $r_update = http_put('/api/admin/licenses/' . $id, ['max_devices' => 1], admin_headers());
    assert_status($r_update, 200);

    // adm-m1 and adm-m2 are still active; a third machine should fail
    $r3 = http_post('/api/license/activate', ['license_key' => $key, 'machine_id' => 'adm-m3']);
    assert_status($r3, 403, 'third device blocked after reducing max_devices');
});

test('[Admin Flow] admin revokes, client verify returns valid=false', function () {
    $id  = $GLOBALS['admin_lic']['id'];
    $key = $GLOBALS['admin_lic']['license_key'];

    $r_del = http_delete('/api/admin/licenses/' . $id, admin_headers());
    assert_status($r_del, 200);
    assert_eq(true, $r_del['body']['revoked']);

    $r_ver = http_post('/api/license/verify', ['license_key' => $key]);
    assert_status($r_ver, 200);
    assert_eq(false, $r_ver['body']['valid']);
    assert_eq('revoked', $r_ver['body']['license']['status']);
});

// ─── Flow 3: Rate-limit DB-level test ─────────────────────────────────────

test('[Rate Limit Flow] 5 rows for IP=127.0.0.1, 6th signup returns 429', function () {
    // This tests the DB-level rate-limit code path.
    // NOTE: The PHP dev server always presents REMOTE_ADDR=127.0.0.1, so a direct
    // HTTP test would clash with other test state. We insert rows directly here to
    // simulate 5 recent signups from the same IP, then fire a real HTTP request.
    // This confirms the signup handler reads ip_address from email_verifications correctly.

    $pdo = harness_db();
    for ($i = 0; $i < 5; $i++) {
        $token = bin2hex(random_bytes(32));
        $pdo->exec("
            INSERT INTO email_verifications (email, token, expires_at, ip_address)
            VALUES ('rl_{$i}@speechy-test.invalid', '{$token}', NOW() + INTERVAL '24 hours', '127.0.0.1')
        ");
    }

    $r = http_post('/api/signup', ['email' => 'rl_new@speechy-test.invalid']);
    assert_status($r, 429);
    assert_true(str_contains($r['body']['error'], 'Too many requests'), 'rate limit message');
});
