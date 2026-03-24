<?php

function generate_license_key(): string
{
    return bin2hex(random_bytes(24));
}

function json_response(array $data, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function json_error(string $message, int $status = 400): void
{
    json_response(['error' => $message], $status);
}

function get_json_body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === '' || $raw === false) {
        return [];
    }

    // Reject oversized payloads (64 KB max)
    if (strlen($raw) > 65536) {
        json_error('Request body too large', 413);
    }

    $data = json_decode($raw, true);
    if (!is_array($data)) {
        json_error('Invalid JSON body', 400);
    }

    return $data;
}

function require_admin_auth(): void
{
    $config = require __DIR__ . '/config.php';
    $provided = $_SERVER['HTTP_X_API_KEY'] ?? '';

    if ($provided === '' || !hash_equals($config['admin_api_key'], $provided)) {
        json_error('Unauthorized', 401);
    }
}

/**
 * Validate and truncate a string input to a max length.
 * Returns trimmed string or empty string if input is not a string.
 */
function sanitize_string($value, int $max_length): string
{
    if (!is_string($value)) {
        return '';
    }
    $value = trim($value);
    if (mb_strlen($value) > $max_length) {
        return mb_substr($value, 0, $max_length);
    }
    return $value;
}

function validate_email(string $email): bool
{
    return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
}

function is_license_expired(array $license): bool
{
    if ($license['license_type'] === 'lifetime') {
        return false;
    }

    if ($license['expires_at'] === null) {
        return false;
    }

    return strtotime($license['expires_at']) < time();
}

function auto_expire_license(PDO $pdo, array &$license): void
{
    if ($license['status'] === 'active' && is_license_expired($license)) {
        $stmt = $pdo->prepare('UPDATE licenses SET status = :status WHERE id = :id');
        $stmt->execute(['status' => 'expired', 'id' => $license['id']]);
        $license['status'] = 'expired';
    }
}

function calculate_expiry(string $license_type, int $trial_days = 90): ?string
{
    switch ($license_type) {
        case 'monthly':
            return date('c', strtotime('+30 days'));
        case 'yearly':
            return date('c', strtotime('+365 days'));
        case 'trial':
            return date('c', strtotime("+{$trial_days} days"));
        case 'lifetime':
        default:
            return null;
    }
}

function parse_route(string $method, string $path): array
{
    return ['method' => $method, 'path' => $path];
}
