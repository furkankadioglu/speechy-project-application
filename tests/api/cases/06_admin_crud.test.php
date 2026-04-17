<?php
/**
 * Test suite: Admin CRUD endpoints
 */

require_once __DIR__ . '/../lib/harness.php';

setup();
suite_header('06 — Admin CRUD');

// ─── Auth ──────────────────────────────────────────────────────────────────

test('GET /api/admin/licenses without API key returns 401', function () {
    $r = http_get('/api/admin/licenses');
    assert_status($r, 401);
});

test('GET /api/admin/licenses with wrong API key returns 401', function () {
    $r = http_get('/api/admin/licenses', ['X-API-Key: wrong-key']);
    assert_status($r, 401);
});

// ─── List ──────────────────────────────────────────────────────────────────

test('GET /api/admin/licenses returns paginated list', function () {
    // Seed some licenses
    db_insert_license('yearly', 'a@speechy-test.invalid');
    db_insert_license('monthly', 'b@speechy-test.invalid');
    db_insert_license('lifetime', 'c@speechy-test.invalid');

    $r = http_get('/api/admin/licenses', admin_headers());
    assert_status($r, 200);
    assert_true(isset($r['body']['licenses']), 'licenses key');
    assert_true(isset($r['body']['pagination']), 'pagination key');
    assert_eq(3, (int)$r['body']['pagination']['total'], 'total=3');
});

test('filter by status=active returns only active', function () {
    // Mark one as revoked
    $lic = db_fetch_one("SELECT id FROM licenses LIMIT 1");
    harness_db()->exec("UPDATE licenses SET status = 'revoked' WHERE id = {$lic['id']}");

    $r = http_get('/api/admin/licenses?status=active', admin_headers());
    assert_status($r, 200);
    foreach ($r['body']['licenses'] as $l) {
        assert_eq('active', $l['status'], 'all listed are active');
    }
});

test('filter by license_type=yearly returns only yearly', function () {
    $r = http_get('/api/admin/licenses?license_type=yearly', admin_headers());
    assert_status($r, 200);
    foreach ($r['body']['licenses'] as $l) {
        assert_eq('yearly', $l['license_type'], 'all listed are yearly');
    }
});

test('filter by email partial match', function () {
    $r = http_get('/api/admin/licenses?email=a%40speechy', admin_headers());
    assert_status($r, 200);
    assert_eq(1, count($r['body']['licenses']), 'one match for email partial');
});

test('pagination per_page clamp: per_page=0 becomes 1', function () {
    $r = http_get('/api/admin/licenses?per_page=0', admin_headers());
    assert_status($r, 200);
    assert_eq(1, (int)$r['body']['pagination']['per_page'], 'clamped to 1');
});

test('pagination per_page clamp: per_page=999 becomes 100', function () {
    $r = http_get('/api/admin/licenses?per_page=999', admin_headers());
    assert_status($r, 200);
    assert_eq(100, (int)$r['body']['pagination']['per_page'], 'clamped to 100');
});

// ─── Create ────────────────────────────────────────────────────────────────

test('create yearly license returns 201 with license', function () {
    $r = http_post('/api/admin/licenses', [
        'license_type' => 'yearly',
        'owner_email'  => 'newuser@speechy-test.invalid',
        'max_devices'  => 2,
    ], admin_headers());
    assert_status($r, 201);
    assert_eq('yearly', $r['body']['license']['license_type']);
    assert_eq('active', $r['body']['license']['status']);
    assert_eq(2, (int)$r['body']['license']['max_devices']);
    assert_true(isset($r['body']['license']['license_key']), 'license_key present');
});

test('create monthly license returns 201', function () {
    $r = http_post('/api/admin/licenses', [
        'license_type' => 'monthly',
    ], admin_headers());
    assert_status($r, 201);
    assert_eq('monthly', $r['body']['license']['license_type']);
    assert_true($r['body']['license']['expires_at'] !== null, 'expiry set');
});

test('create lifetime license has no expiry', function () {
    $r = http_post('/api/admin/licenses', [
        'license_type' => 'lifetime',
    ], admin_headers());
    assert_status($r, 201);
    assert_eq(null, $r['body']['license']['expires_at'], 'no expiry for lifetime');
});

test('create with invalid license_type returns 400', function () {
    $r = http_post('/api/admin/licenses', ['license_type' => 'trial'], admin_headers());
    assert_status($r, 400);
});

test('create trial via /api/admin/licenses/trial returns 201', function () {
    $r = http_post('/api/admin/licenses/trial', [
        'owner_email' => 'trialuser@speechy-test.invalid',
        'owner_name'  => 'Trial User',
    ], admin_headers());
    assert_status($r, 201);
    assert_eq('trial', $r['body']['license']['license_type']);
});

test('create trial duplicate email returns 409', function () {
    $r = http_post('/api/admin/licenses/trial', [
        'owner_email' => 'trialuser@speechy-test.invalid',
    ], admin_headers());
    assert_status($r, 409);
    assert_true(str_contains($r['body']['error'], 'trial license'), 'duplicate trial error');
});

// ─── Get single ────────────────────────────────────────────────────────────

test('GET /api/admin/licenses/{id} includes activations array', function () {
    // Create a fresh active license to ensure activation succeeds
    $lic = db_insert_license('yearly', 'get-single@speechy-test.invalid');
    $ra  = http_post('/api/license/activate', ['license_key' => $lic['license_key'], 'machine_id' => 'admin-test-m1']);
    assert_status($ra, 200, 'activation for admin get test succeeded');

    $r = http_get('/api/admin/licenses/' . $lic['id'], admin_headers());
    assert_status($r, 200);
    assert_true(isset($r['body']['license']), 'license key present');
    assert_true(isset($r['body']['activations']), 'activations key present');
    assert_true(count($r['body']['activations']) >= 1, 'at least one activation');
});

test('GET /api/admin/licenses/9999 returns 404', function () {
    $r = http_get('/api/admin/licenses/9999', admin_headers());
    assert_status($r, 404);
});

// ─── Update ────────────────────────────────────────────────────────────────

test('PUT /api/admin/licenses/{id} updates status', function () {
    $lic = db_fetch_one("SELECT id FROM licenses WHERE status = 'active' LIMIT 1");
    $r   = http_put('/api/admin/licenses/' . $lic['id'], ['status' => 'suspended'], admin_headers());
    assert_status($r, 200);
    assert_eq('suspended', $r['body']['license']['status']);
});

test('PUT /api/admin/licenses/{id} updates max_devices', function () {
    $lic = db_fetch_one("SELECT id FROM licenses LIMIT 1");
    $r   = http_put('/api/admin/licenses/' . $lic['id'], ['max_devices' => 5], admin_headers());
    assert_status($r, 200);
    assert_eq(5, (int)$r['body']['license']['max_devices']);
});

test('PUT /api/admin/licenses/{id} with invalid status returns 400', function () {
    $lic = db_fetch_one("SELECT id FROM licenses LIMIT 1");
    $r   = http_put('/api/admin/licenses/' . $lic['id'], ['status' => 'unknown'], admin_headers());
    assert_status($r, 400);
});

test('PUT /api/admin/licenses/9999 returns 404', function () {
    $r = http_put('/api/admin/licenses/9999', ['max_devices' => 2], admin_headers());
    assert_status($r, 404);
});

// ─── Delete (soft revoke) ──────────────────────────────────────────────────

test('DELETE /api/admin/licenses/{id} soft-revokes the license', function () {
    $lic = db_insert_license('monthly', 'deleteme@speechy-test.invalid');
    $r   = http_delete('/api/admin/licenses/' . $lic['id'], admin_headers());
    assert_status($r, 200);
    assert_eq(true, $r['body']['revoked']);
    assert_eq('revoked', $r['body']['license']['status']);
    // Verify in DB
    $row = db_fetch_one('SELECT status FROM licenses WHERE id = :id', ['id' => $lic['id']]);
    assert_eq('revoked', $row['status'], 'DB status = revoked');
});

test('DELETE /api/admin/licenses/9999 returns 404', function () {
    $r = http_delete('/api/admin/licenses/9999', admin_headers());
    assert_status($r, 404);
});
