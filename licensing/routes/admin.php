<?php

function handle_admin_route(string $method, string $path): bool
{
    // All admin routes require auth
    if (strpos($path, '/api/admin/') !== 0) {
        return false;
    }

    require_admin_auth();

    // POST /api/admin/licenses/trial
    if ($method === 'POST' && $path === '/api/admin/licenses/trial') {
        handle_admin_create_trial();
        return true;
    }

    // GET /api/admin/licenses
    if ($method === 'GET' && $path === '/api/admin/licenses') {
        handle_admin_list_licenses();
        return true;
    }

    // POST /api/admin/licenses
    if ($method === 'POST' && $path === '/api/admin/licenses') {
        handle_admin_create_license();
        return true;
    }

    // Routes with {id}
    if (preg_match('#^/api/admin/licenses/(\d+)$#', $path, $matches)) {
        $id = (int) $matches[1];

        if ($method === 'GET') {
            handle_admin_get_license($id);
            return true;
        }

        if ($method === 'PUT') {
            handle_admin_update_license($id);
            return true;
        }

        if ($method === 'DELETE') {
            handle_admin_delete_license($id);
            return true;
        }
    }

    return false;
}

function handle_admin_list_licenses(): void
{
    $pdo = get_db();

    $page = max(1, (int) ($_GET['page'] ?? 1));
    $per_page = min(100, max(1, (int) ($_GET['per_page'] ?? 20)));
    $offset = ($page - 1) * $per_page;

    $where = [];
    $params = [];

    if (!empty($_GET['status'])) {
        $status = sanitize_string($_GET['status'], 16);
        $valid_statuses = ['active', 'expired', 'revoked', 'suspended'];
        if (in_array($status, $valid_statuses, true)) {
            $where[] = 'status = :status';
            $params['status'] = $status;
        }
    }

    if (!empty($_GET['license_type'])) {
        $type = sanitize_string($_GET['license_type'], 16);
        $valid_types = ['trial', 'monthly', 'yearly', 'lifetime'];
        if (in_array($type, $valid_types, true)) {
            $where[] = 'license_type = :license_type';
            $params['license_type'] = $type;
        }
    }

    if (!empty($_GET['email'])) {
        $email = sanitize_string($_GET['email'], 255);
        if ($email !== '') {
            $where[] = 'owner_email ILIKE :email';
            $params['email'] = '%' . $email . '%';
        }
    }

    $where_sql = $where ? 'WHERE ' . implode(' AND ', $where) : '';

    // Count total
    $count_stmt = $pdo->prepare("SELECT COUNT(*) FROM licenses {$where_sql}");
    $count_stmt->execute($params);
    $total = (int) $count_stmt->fetchColumn();

    // Fetch page
    $stmt = $pdo->prepare(
        "SELECT * FROM licenses {$where_sql} ORDER BY created_at DESC LIMIT :limit OFFSET :offset"
    );
    foreach ($params as $key => $value) {
        $stmt->bindValue($key, $value);
    }
    $stmt->bindValue('limit', $per_page, PDO::PARAM_INT);
    $stmt->bindValue('offset', $offset, PDO::PARAM_INT);
    $stmt->execute();

    $licenses = $stmt->fetchAll();

    // Auto-expire
    foreach ($licenses as &$license) {
        auto_expire_license($pdo, $license);
    }
    unset($license);

    json_response([
        'licenses' => $licenses,
        'pagination' => [
            'page' => $page,
            'per_page' => $per_page,
            'total' => $total,
            'total_pages' => (int) ceil($total / $per_page),
        ],
    ]);
}

function handle_admin_get_license(int $id): void
{
    $pdo = get_db();

    $stmt = $pdo->prepare('SELECT * FROM licenses WHERE id = :id');
    $stmt->execute(['id' => $id]);
    $license = $stmt->fetch();

    if (!$license) {
        json_error('License not found', 404);
    }

    auto_expire_license($pdo, $license);

    // Fetch activations
    $stmt = $pdo->prepare(
        'SELECT * FROM activations WHERE license_id = :lid ORDER BY activated_at DESC'
    );
    $stmt->execute(['lid' => $id]);
    $activations = $stmt->fetchAll();

    json_response([
        'license' => $license,
        'activations' => $activations,
    ]);
}

function handle_admin_create_license(): void
{
    $body = get_json_body();
    $license_type = sanitize_string($body['license_type'] ?? '', 16);

    if (!in_array($license_type, ['monthly', 'yearly', 'lifetime'], true)) {
        json_error('license_type must be monthly, yearly, or lifetime');
    }

    $owner_email = sanitize_string($body['owner_email'] ?? '', 255);
    if ($owner_email !== '' && !validate_email($owner_email)) {
        json_error('Invalid email format');
    }

    $max_devices = (int) ($body['max_devices'] ?? 1);
    if ($max_devices < 1 || $max_devices > 100) {
        json_error('max_devices must be between 1 and 100');
    }

    $pdo = get_db();
    $key = generate_license_key();
    $expires_at = calculate_expiry($license_type);

    $stmt = $pdo->prepare('
        INSERT INTO licenses (license_key, license_type, owner_email, owner_name, notes, expires_at, max_devices)
        VALUES (:key, :type, :email, :name, :notes, :expires, :max_devices)
        RETURNING *
    ');
    $stmt->execute([
        'key' => $key,
        'type' => $license_type,
        'email' => $owner_email !== '' ? $owner_email : null,
        'name' => sanitize_string($body['owner_name'] ?? '', 255) ?: null,
        'notes' => sanitize_string($body['notes'] ?? '', 1000) ?: null,
        'expires' => $expires_at,
        'max_devices' => $max_devices,
    ]);

    $license = $stmt->fetch();

    // Send license email if owner email is provided
    if ($owner_email !== '') {
        send_license_email($owner_email, $license['license_key'], $license_type, $license['expires_at']);
    }

    json_response(['license' => $license], 201);
}

function handle_admin_create_trial(): void
{
    $body = get_json_body();
    $email = sanitize_string($body['owner_email'] ?? '', 255);

    if ($email === '') {
        json_error('owner_email is required for trial licenses');
    }

    if (!validate_email($email)) {
        json_error('Invalid email format');
    }

    $config = require __DIR__ . '/../config.php';
    $trial_days = $config['trial_duration_days'] ?? 90;

    $pdo = get_db();

    $key = generate_license_key();
    $expires_at = calculate_expiry('trial', $trial_days);

    // Transaction with row-level lock to prevent race condition.
    // Backed by partial unique index (idx_licenses_one_trial_per_email) as a DB-level safety net.
    $pdo->beginTransaction();

    try {
        // Check-and-insert within a serializable scope using FOR UPDATE
        $check = $pdo->prepare(
            'SELECT id FROM licenses WHERE owner_email = :email AND license_type = :type FOR UPDATE'
        );
        $check->execute(['email' => $email, 'type' => 'trial']);

        if ($check->fetch()) {
            $pdo->rollBack();
            json_error('A trial license already exists for this email', 409);
        }

        $stmt = $pdo->prepare('
            INSERT INTO licenses (license_key, license_type, owner_email, owner_name, notes, expires_at)
            VALUES (:key, :type, :email, :name, :notes, :expires)
            RETURNING *
        ');
        $stmt->execute([
            'key' => $key,
            'type' => 'trial',
            'email' => $email,
            'name' => sanitize_string($body['owner_name'] ?? '', 255) ?: null,
            'notes' => sanitize_string($body['notes'] ?? '', 1000) ?: null,
            'expires' => $expires_at,
        ]);

        $license = $stmt->fetch();
        $pdo->commit();
    } catch (PDOException $e) {
        $pdo->rollBack();
        json_error('Failed to create trial license', 500);
    }

    json_response(['license' => $license], 201);
}

function handle_admin_update_license(int $id): void
{
    $body = get_json_body();

    $pdo = get_db();

    // Verify license exists
    $stmt = $pdo->prepare('SELECT * FROM licenses WHERE id = :id');
    $stmt->execute(['id' => $id]);
    $license = $stmt->fetch();

    if (!$license) {
        json_error('License not found', 404);
    }

    $allowed = ['status', 'owner_email', 'owner_name', 'notes', 'expires_at', 'max_devices'];
    $sets = [];
    $params = ['id' => $id];

    foreach ($allowed as $field) {
        if (array_key_exists($field, $body)) {
            $sets[] = "{$field} = :{$field}";
            $params[$field] = $body[$field];
        }
    }

    if (empty($sets)) {
        json_error('No valid fields to update');
    }

    // Validate status if provided
    if (isset($params['status'])) {
        $valid_statuses = ['active', 'expired', 'revoked', 'suspended'];
        if (!is_string($params['status']) || !in_array($params['status'], $valid_statuses, true)) {
            json_error('Invalid status. Must be: ' . implode(', ', $valid_statuses));
        }
    }

    // Validate email if provided
    if (isset($params['owner_email']) && $params['owner_email'] !== null) {
        $params['owner_email'] = sanitize_string($params['owner_email'], 255);
        if ($params['owner_email'] !== '' && !validate_email($params['owner_email'])) {
            json_error('Invalid email format');
        }
    }

    // Validate max_devices if provided
    if (isset($params['max_devices'])) {
        $params['max_devices'] = (int) $params['max_devices'];
        if ($params['max_devices'] < 1 || $params['max_devices'] > 100) {
            json_error('max_devices must be between 1 and 100');
        }
    }

    // Sanitize string fields
    if (isset($params['owner_name'])) {
        $params['owner_name'] = sanitize_string($params['owner_name'] ?? '', 255) ?: null;
    }
    if (isset($params['notes'])) {
        $params['notes'] = sanitize_string($params['notes'] ?? '', 1000) ?: null;
    }

    $set_sql = implode(', ', $sets);
    $stmt = $pdo->prepare("UPDATE licenses SET {$set_sql} WHERE id = :id RETURNING *");
    $stmt->execute($params);

    $license = $stmt->fetch();

    json_response(['license' => $license]);
}

function handle_admin_delete_license(int $id): void
{
    $pdo = get_db();

    $stmt = $pdo->prepare('SELECT id FROM licenses WHERE id = :id');
    $stmt->execute(['id' => $id]);

    if (!$stmt->fetch()) {
        json_error('License not found', 404);
    }

    // Soft-delete: set status to revoked
    $stmt = $pdo->prepare('UPDATE licenses SET status = :status WHERE id = :id RETURNING *');
    $stmt->execute(['status' => 'revoked', 'id' => $id]);

    $license = $stmt->fetch();

    json_response([
        'revoked' => true,
        'license' => $license,
    ]);
}
