<?php

// Block direct access to internal files via PHP built-in server
$requested = $_SERVER['SCRIPT_NAME'] ?? '';
$blocked = ['/config.php', '/config.example.php', '/db.php', '/helpers.php', '/migrate.php'];
foreach ($blocked as $file) {
    if ($requested === $file || strpos($requested, '/migrations/') === 0) {
        http_response_code(404);
        exit;
    }
}

require __DIR__ . '/db.php';
require __DIR__ . '/helpers.php';
require __DIR__ . '/email.php';
require __DIR__ . '/routes/app.php';
require __DIR__ . '/routes/admin.php';
require __DIR__ . '/routes/signup.php';
require __DIR__ . '/routes/receipt.php';

// CORS headers — restrict admin routes, allow app clients
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$is_admin = strpos($path, '/api/admin/') === 0;

if (!$is_admin) {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
}

// Handle preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

try {
    $method = $_SERVER['REQUEST_METHOD'];

    // Try admin routes first, then app routes
    if (handle_admin_route($method, $path)) {
        exit;
    }

    if (handle_app_route($method, $path)) {
        exit;
    }

    if (handle_signup_route($method, $path)) {
        exit;
    }

    if (handle_receipt_route($method, $path)) {
        exit;
    }

    json_error('Not found', 404);
} catch (PDOException $e) {
    json_error('Internal server error', 500);
} catch (Throwable $e) {
    json_error('Internal server error', 500);
}
