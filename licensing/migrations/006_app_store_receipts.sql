-- Mac App Store one-time purchase receipts
-- Each verified receipt corresponds to a single Apple ID purchase of Speechy.
-- transaction_id is Apple's unique identifier for the purchase event.

CREATE TABLE IF NOT EXISTS app_store_receipts (
    id SERIAL PRIMARY KEY,
    transaction_id VARCHAR(64) NOT NULL UNIQUE,
    original_transaction_id VARCHAR(64),
    bundle_id VARCHAR(128) NOT NULL,
    product_id VARCHAR(128),
    purchase_date TIMESTAMPTZ,
    original_purchase_date TIMESTAMPTZ,
    receipt_b64 TEXT NOT NULL,
    apple_environment VARCHAR(16) CHECK (apple_environment IN ('Production', 'Sandbox')),
    last_verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_valid BOOLEAN NOT NULL DEFAULT TRUE,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_app_store_receipts_transaction_id ON app_store_receipts (transaction_id);
CREATE INDEX idx_app_store_receipts_bundle_id ON app_store_receipts (bundle_id);
CREATE INDEX idx_app_store_receipts_is_valid ON app_store_receipts (is_valid);
