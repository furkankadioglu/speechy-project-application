<?php

// Mac App Store receipt verification.
// Desktop app POSTs the base64 receipt; we forward to Apple's verifyReceipt endpoint
// (production with sandbox fallback) and cache the result by transaction_id.

const APPLE_PRODUCTION_URL = 'https://buy.itunes.apple.com/verifyReceipt';
const APPLE_SANDBOX_URL = 'https://sandbox.itunes.apple.com/verifyReceipt';
const SPEECHY_BUNDLE_ID = 'com.speechy.app';

function handle_receipt_route(string $method, string $path): bool
{
    if ($method === 'POST' && $path === '/api/receipt/verify') {
        handle_receipt_verify();
        return true;
    }
    return false;
}

function handle_receipt_verify(): void
{
    $body = get_json_body();
    $receipt_b64 = $body['receipt'] ?? '';
    $bundle_id = sanitize_string($body['bundle_id'] ?? '', 128);

    if ($receipt_b64 === '' || !is_string($receipt_b64)) {
        json_error('receipt is required');
    }

    if ($bundle_id !== SPEECHY_BUNDLE_ID) {
        json_error('Invalid bundle_id', 403);
    }

    if (strlen($receipt_b64) > 1_500_000) {
        json_error('receipt too large', 413);
    }

    // Apple verifyReceipt — shared secret is optional for one-time purchases,
    // required for auto-renewable subscriptions. We carry it for forward-compat.
    $config = require __DIR__ . '/../config.php';
    $shared_secret = $config['appstore_shared_secret'] ?? '';
    $payload = ['receipt-data' => $receipt_b64];
    if ($shared_secret !== '') {
        $payload['password'] = $shared_secret;
    }

    [$apple_status, $apple_response, $environment] = call_apple_verify($payload);

    if ($apple_status !== 0) {
        // Apple status codes: https://developer.apple.com/documentation/appstorereceipts/status
        json_response([
            'valid' => false,
            'error' => 'Apple verification failed',
            'apple_status' => $apple_status,
        ]);
        return;
    }

    $apple_receipt = $apple_response['receipt'] ?? [];
    $apple_bundle = $apple_receipt['bundle_id'] ?? '';
    if ($apple_bundle !== SPEECHY_BUNDLE_ID) {
        json_response(['valid' => false, 'error' => 'Bundle ID mismatch']);
        return;
    }

    // For one-time purchases the transaction sits in `in_app`; pick the latest one.
    $in_app = $apple_receipt['in_app'] ?? [];
    if (empty($in_app)) {
        // Receipt is valid (status 0) but no purchase recorded → app still under refund/grace
        json_response(['valid' => false, 'error' => 'No purchase in receipt']);
        return;
    }

    // Latest purchase = highest purchase_date_ms
    usort($in_app, function ($a, $b) {
        return (int) ($b['purchase_date_ms'] ?? 0) <=> (int) ($a['purchase_date_ms'] ?? 0);
    });
    $purchase = $in_app[0];

    $transaction_id = $purchase['transaction_id'] ?? '';
    $original_transaction_id = $purchase['original_transaction_id'] ?? $transaction_id;
    $product_id = $purchase['product_id'] ?? '';
    $purchase_date_ms = (int) ($purchase['purchase_date_ms'] ?? 0);
    $original_purchase_date_ms = (int) ($purchase['original_purchase_date_ms'] ?? $purchase_date_ms);

    if ($transaction_id === '') {
        json_response(['valid' => false, 'error' => 'Missing transaction_id']);
        return;
    }

    // Refund detection — Apple includes `cancellation_date` for refunded transactions
    if (!empty($purchase['cancellation_date_ms'])) {
        // Mark as revoked
        record_receipt(
            $transaction_id,
            $original_transaction_id,
            $bundle_id,
            $product_id,
            $purchase_date_ms,
            $original_purchase_date_ms,
            $receipt_b64,
            $environment,
            false
        );
        json_response(['valid' => false, 'error' => 'Purchase refunded']);
        return;
    }

    // Persist / refresh receipt record
    record_receipt(
        $transaction_id,
        $original_transaction_id,
        $bundle_id,
        $product_id,
        $purchase_date_ms,
        $original_purchase_date_ms,
        $receipt_b64,
        $environment,
        true
    );

    json_response([
        'valid' => true,
        'transaction_id' => $transaction_id,
        'original_transaction_id' => $original_transaction_id,
        'product_id' => $product_id,
        'environment' => $environment,
        'purchase_date' => $purchase_date_ms > 0 ? date('c', (int) ($purchase_date_ms / 1000)) : null,
    ]);
}

/**
 * Calls Apple's verifyReceipt endpoint. Tries production first; if Apple replies with
 * 21007 (sandbox receipt sent to production) it retries against sandbox.
 *
 * @return array{0:int,1:array,2:string} [apple_status, full_response, environment]
 */
function call_apple_verify(array $payload): array
{
    $response = http_post_json(APPLE_PRODUCTION_URL, $payload);
    $status = (int) ($response['status'] ?? -1);

    if ($status === 21007) {
        $response = http_post_json(APPLE_SANDBOX_URL, $payload);
        $status = (int) ($response['status'] ?? -1);
        return [$status, $response, 'Sandbox'];
    }

    return [$status, $response, 'Production'];
}

function http_post_json(string $url, array $payload): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    $body = curl_exec($ch);
    $err = curl_error($ch);
    curl_close($ch);

    if ($body === false) {
        return ['status' => -1, 'error' => $err];
    }

    $decoded = json_decode($body, true);
    if (!is_array($decoded)) {
        return ['status' => -1, 'error' => 'Invalid Apple response'];
    }

    return $decoded;
}

function record_receipt(
    string $transaction_id,
    string $original_transaction_id,
    string $bundle_id,
    string $product_id,
    int $purchase_date_ms,
    int $original_purchase_date_ms,
    string $receipt_b64,
    string $environment,
    bool $is_valid
): void {
    $pdo = get_db();
    $stmt = $pdo->prepare('
        INSERT INTO app_store_receipts (
            transaction_id, original_transaction_id, bundle_id, product_id,
            purchase_date, original_purchase_date, receipt_b64, apple_environment,
            last_verified_at, is_valid, revoked_at
        ) VALUES (
            :tid, :otid, :bid, :pid,
            to_timestamp(:pdate), to_timestamp(:opdate), :receipt, :env,
            NOW(), :valid, :revoked
        )
        ON CONFLICT (transaction_id) DO UPDATE SET
            receipt_b64 = EXCLUDED.receipt_b64,
            apple_environment = EXCLUDED.apple_environment,
            last_verified_at = NOW(),
            is_valid = EXCLUDED.is_valid,
            revoked_at = CASE WHEN EXCLUDED.is_valid THEN NULL ELSE NOW() END
    ');
    $stmt->execute([
        'tid' => $transaction_id,
        'otid' => $original_transaction_id,
        'bid' => $bundle_id,
        'pid' => $product_id,
        'pdate' => $purchase_date_ms / 1000,
        'opdate' => $original_purchase_date_ms / 1000,
        'receipt' => $receipt_b64,
        'env' => $environment,
        'valid' => $is_valid ? 't' : 'f',
        'revoked' => $is_valid ? null : date('c'),
    ]);
}
