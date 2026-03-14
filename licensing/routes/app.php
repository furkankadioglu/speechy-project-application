<?php

function handle_app_route(string $method, string $path): bool
{
    if ($method === 'POST' && $path === '/api/license/verify') {
        handle_verify();
        return true;
    }

    if ($method === 'POST' && $path === '/api/license/activate') {
        handle_activate();
        return true;
    }

    if ($method === 'POST' && $path === '/api/license/deactivate') {
        handle_deactivate();
        return true;
    }

    return false;
}

function handle_verify(): void
{
    $body = get_json_body();
    $license_key = sanitize_string($body['license_key'] ?? '', 64);

    if ($license_key === '') {
        json_error('license_key is required');
    }

    $pdo = get_db();

    $stmt = $pdo->prepare('SELECT * FROM licenses WHERE license_key = :key');
    $stmt->execute(['key' => $license_key]);
    $license = $stmt->fetch();

    if (!$license) {
        json_error('Invalid license key', 404);
    }

    auto_expire_license($pdo, $license);

    $valid = $license['status'] === 'active';

    json_response([
        'valid' => $valid,
        'license' => [
            'license_type' => $license['license_type'],
            'status' => $license['status'],
            'expires_at' => $license['expires_at'],
            'max_devices' => (int) $license['max_devices'],
        ],
    ]);
}

function handle_activate(): void
{
    $body = get_json_body();
    $license_key = sanitize_string($body['license_key'] ?? '', 64);
    $machine_id = sanitize_string($body['machine_id'] ?? '', 255);
    $machine_label = sanitize_string($body['machine_label'] ?? '', 255);
    $app_platform = sanitize_string($body['app_platform'] ?? '', 16);
    $app_version = sanitize_string($body['app_version'] ?? '', 32);

    if ($license_key === '' || $machine_id === '') {
        json_error('license_key and machine_id are required');
    }

    if ($app_platform !== '' && !in_array($app_platform, ['macos', 'windows', 'ios'], true)) {
        json_error('app_platform must be macos, windows, or ios');
    }

    $pdo = get_db();
    $pdo->beginTransaction();

    try {
        // Lock the license row to prevent race conditions on device count
        $stmt = $pdo->prepare('SELECT * FROM licenses WHERE license_key = :key FOR UPDATE');
        $stmt->execute(['key' => $license_key]);
        $license = $stmt->fetch();

        if (!$license) {
            $pdo->rollBack();
            json_error('Invalid license key', 404);
        }

        auto_expire_license($pdo, $license);

        if ($license['status'] !== 'active') {
            $pdo->rollBack();
            json_error('License is ' . $license['status'], 403);
        }

        // Check if this machine is already activated for this license
        $stmt = $pdo->prepare(
            'SELECT id FROM activations WHERE license_id = :lid AND machine_id = :mid AND is_active = TRUE'
        );
        $stmt->execute(['lid' => $license['id'], 'mid' => $machine_id]);
        $existing = $stmt->fetch();

        if ($existing) {
            $pdo->commit();
            json_response([
                'activated' => true,
                'message' => 'Device already activated',
            ]);
            return;
        }

        // Count active activations (accurate because we hold the row lock)
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM activations WHERE license_id = :lid AND is_active = TRUE'
        );
        $stmt->execute(['lid' => $license['id']]);
        $active_count = (int) $stmt->fetchColumn();

        if ($active_count >= (int) $license['max_devices']) {
            $pdo->rollBack();
            json_error(
                'Device limit reached (' . (int) $license['max_devices'] . '). Deactivate another device first.',
                403
            );
        }

        // Create activation record
        $stmt = $pdo->prepare('
            INSERT INTO activations (license_id, machine_id, machine_label, app_platform, app_version)
            VALUES (:lid, :mid, :mlabel, :platform, :version)
        ');
        $stmt->execute([
            'lid' => $license['id'],
            'mid' => $machine_id,
            'mlabel' => $machine_label !== '' ? $machine_label : null,
            'platform' => $app_platform !== '' ? $app_platform : null,
            'version' => $app_version !== '' ? $app_version : null,
        ]);

        // Update license with first activation info if not yet activated
        if ($license['activated_at'] === null) {
            $stmt = $pdo->prepare('
                UPDATE licenses
                SET activated_at = NOW(), machine_id = :mid, machine_label = :mlabel, app_platform = :platform
                WHERE id = :id
            ');
            $stmt->execute([
                'mid' => $machine_id,
                'mlabel' => $machine_label !== '' ? $machine_label : null,
                'platform' => $app_platform !== '' ? $app_platform : null,
                'id' => $license['id'],
            ]);
        }

        $pdo->commit();
    } catch (PDOException $e) {
        $pdo->rollBack();
        json_error('Activation failed', 500);
    }

    json_response([
        'activated' => true,
        'message' => 'Device activated successfully',
    ]);
}

function handle_deactivate(): void
{
    $body = get_json_body();
    $license_key = sanitize_string($body['license_key'] ?? '', 64);
    $machine_id = sanitize_string($body['machine_id'] ?? '', 255);

    if ($license_key === '' || $machine_id === '') {
        json_error('license_key and machine_id are required');
    }

    $pdo = get_db();

    $stmt = $pdo->prepare('SELECT id FROM licenses WHERE license_key = :key');
    $stmt->execute(['key' => $license_key]);
    $license = $stmt->fetch();

    if (!$license) {
        json_error('Invalid license key', 404);
    }

    // Deactivate the activation record
    $stmt = $pdo->prepare('
        UPDATE activations
        SET is_active = FALSE, deactivated_at = NOW()
        WHERE license_id = :lid AND machine_id = :mid AND is_active = TRUE
    ');
    $stmt->execute(['lid' => $license['id'], 'mid' => $machine_id]);

    if ($stmt->rowCount() === 0) {
        json_error('No active activation found for this device', 404);
    }

    json_response([
        'deactivated' => true,
        'message' => 'Device deactivated successfully',
    ]);
}
