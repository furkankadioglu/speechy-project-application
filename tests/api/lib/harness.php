<?php
/**
 * Speechy API Test Harness
 * Lightweight, dependency-free test runner used by all tests/api/cases/*.test.php files.
 */

// ─── Configuration (from env) ──────────────────────────────────────────────
define('API_BASE_URL', getenv('API_BASE_URL') ?: 'http://127.0.0.1:8765');
define('ADMIN_API_KEY', getenv('ADMIN_API_KEY') ?: 'test-admin-key-do-not-use');
define('TEST_DB_NAME', getenv('TEST_DB_NAME') ?: 'speechy_licensing_test');
define('TEST_DB_HOST', getenv('TEST_DB_HOST') ?: '127.0.0.1');
define('TEST_DB_PORT', (int)(getenv('TEST_DB_PORT') ?: 5432));
define('TEST_DB_USER', getenv('TEST_DB_USER') ?: get_current_user());
define('TEST_DB_PASS', getenv('TEST_DB_PASS') ?: '');

// ─── State ─────────────────────────────────────────────────────────────────
$HARNESS = [
    'passed'  => 0,
    'failed'  => 0,
    'errors'  => [],
    'current' => '',
];

// ─── PDO (test DB) ─────────────────────────────────────────────────────────
function harness_db(): PDO {
    static $pdo = null;
    if ($pdo !== null) return $pdo;

    $dsn = sprintf('pgsql:host=%s;port=%d;dbname=%s', TEST_DB_HOST, TEST_DB_PORT, TEST_DB_NAME);
    $pdo = new PDO($dsn, TEST_DB_USER, TEST_DB_PASS, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
    return $pdo;
}

// ─── DB Helpers ────────────────────────────────────────────────────────────
function db_truncate_all(): void {
    $pdo = harness_db();
    $pdo->exec('TRUNCATE TABLE activations, email_verifications, licenses RESTART IDENTITY CASCADE');
}

/**
 * Insert a license directly into the DB. Returns the full row array.
 */
function db_insert_license(string $type, ?string $email = null, int $max_devices = 1, string $status = 'active', ?string $expires_at = null): array {
    $pdo = harness_db();

    // Default expiry
    if ($expires_at === null) {
        if ($type === 'lifetime') {
            $expires_at = null;
        } elseif ($type === 'yearly') {
            $expires_at = date('c', strtotime('+365 days'));
        } else {
            $expires_at = date('c', strtotime('+30 days'));
        }
    }

    $key = bin2hex(random_bytes(24));
    $stmt = $pdo->prepare('
        INSERT INTO licenses (license_key, license_type, status, owner_email, expires_at, max_devices)
        VALUES (:key, :type, :status, :email, :expires, :max_devices)
        RETURNING *
    ');
    $stmt->execute([
        'key'         => $key,
        'type'        => $type,
        'status'      => $status,
        'email'       => $email,
        'expires'     => $expires_at,
        'max_devices' => $max_devices,
    ]);
    return $stmt->fetch();
}

function db_count(string $table): int {
    return (int) harness_db()->query("SELECT COUNT(*) FROM {$table}")->fetchColumn();
}

function db_fetch_one(string $sql, array $params = []): ?array {
    $stmt = harness_db()->prepare($sql);
    $stmt->execute($params);
    $row = $stmt->fetch();
    return $row ?: null;
}

// ─── HTTP Helpers ──────────────────────────────────────────────────────────
function _http_request(string $method, string $path, array $body = [], array $headers = []): array {
    $url = API_BASE_URL . $path;
    $ch  = curl_init($url);

    $default_headers = ['Content-Type: application/json', 'Accept: application/json'];
    $all_headers = array_merge($default_headers, $headers);

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER         => true,
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_HTTPHEADER     => $all_headers,
        CURLOPT_TIMEOUT        => 10,
        CURLOPT_CONNECTTIMEOUT => 5,
    ]);

    if (in_array($method, ['POST', 'PUT', 'PATCH'], true)) {
        $json = json_encode($body);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $json);
    }

    $raw      = curl_exec($ch);
    $status   = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $header_size = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    // curl_close() is a no-op since PHP 8.0 and deprecated in 8.5 — suppress the notice
    @curl_close($ch);

    if ($raw === false) {
        throw new RuntimeException("curl request failed: {$url}");
    }

    $raw_headers = substr($raw, 0, $header_size);
    $raw_body    = substr($raw, $header_size);

    // Parse headers
    $parsed_headers = [];
    foreach (explode("\r\n", $raw_headers) as $line) {
        if (str_contains($line, ':')) {
            [$k, $v] = explode(':', $line, 2);
            $parsed_headers[strtolower(trim($k))] = trim($v);
        }
    }

    // Try JSON decode
    $decoded = json_decode($raw_body, true);
    $body_out = ($decoded !== null) ? $decoded : $raw_body;

    return ['status' => $status, 'body' => $body_out, 'headers' => $parsed_headers];
}

function http_get(string $path, array $headers = []): array {
    return _http_request('GET', $path, [], $headers);
}

function http_post(string $path, array $body = [], array $headers = []): array {
    return _http_request('POST', $path, $body, $headers);
}

function http_put(string $path, array $body = [], array $headers = []): array {
    return _http_request('PUT', $path, $body, $headers);
}

function http_delete(string $path, array $headers = []): array {
    return _http_request('DELETE', $path, [], $headers);
}

function admin_headers(): array {
    return ['X-API-Key: ' . ADMIN_API_KEY];
}

// ─── Assertions ────────────────────────────────────────────────────────────
function assert_eq($expected, $actual, string $msg = ''): void {
    global $HARNESS;
    if ($expected !== $actual) {
        $label = $HARNESS['current'] ? "[{$HARNESS['current']}] " : '';
        $detail = $msg ? " — {$msg}" : '';
        throw new AssertionError("{$label}Expected " . json_encode($expected) . " but got " . json_encode($actual) . $detail);
    }
}

function assert_true($cond, string $msg = ''): void {
    global $HARNESS;
    if (!$cond) {
        $label = $HARNESS['current'] ? "[{$HARNESS['current']}] " : '';
        $detail = $msg ? " — {$msg}" : '';
        throw new AssertionError("{$label}Expected true but got false{$detail}");
    }
}

function assert_status(array $response, int $code, string $msg = ''): void {
    global $HARNESS;
    if ($response['status'] !== $code) {
        $label = $HARNESS['current'] ? "[{$HARNESS['current']}] " : '';
        $detail = $msg ? " — {$msg}" : '';
        $body   = is_array($response['body']) ? json_encode($response['body']) : (string)$response['body'];
        throw new AssertionError("{$label}Expected HTTP {$code} but got {$response['status']}{$detail}\nBody: {$body}");
    }
}

// ─── Test Runner ───────────────────────────────────────────────────────────
function test(string $name, callable $fn): void {
    global $HARNESS;
    $HARNESS['current'] = $name;
    try {
        $fn();
        $HARNESS['passed']++;
        echo "\033[32m  ✓\033[0m {$name}\n";
    } catch (AssertionError $e) {
        $HARNESS['failed']++;
        $HARNESS['errors'][] = ['name' => $name, 'error' => $e->getMessage()];
        echo "\033[31m  ✗\033[0m {$name}\n";
        echo "    " . str_replace("\n", "\n    ", $e->getMessage()) . "\n";
    } catch (Throwable $e) {
        $HARNESS['failed']++;
        $HARNESS['errors'][] = ['name' => $name, 'error' => $e->getMessage()];
        echo "\033[31m  ✗\033[0m {$name}\n";
        echo "    " . get_class($e) . ': ' . str_replace("\n", "\n    ", $e->getMessage()) . "\n";
    }
    $HARNESS['current'] = '';
}

function setup(): void {
    db_truncate_all();
}

function suite_header(string $title): void {
    echo "\n\033[1;34m▶ {$title}\033[0m\n";
}

function suite_summary(): array {
    global $HARNESS;
    return ['passed' => $HARNESS['passed'], 'failed' => $HARNESS['failed']];
}
