CREATE TABLE IF NOT EXISTS licenses (
    id SERIAL PRIMARY KEY,
    license_key VARCHAR(64) NOT NULL UNIQUE,
    license_type VARCHAR(16) NOT NULL CHECK (license_type IN ('trial', 'monthly', 'yearly', 'lifetime')),
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'revoked', 'suspended')),
    owner_email VARCHAR(255),
    owner_name VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    activated_at TIMESTAMPTZ,
    machine_id VARCHAR(255),
    machine_label VARCHAR(255),
    app_platform VARCHAR(16) CHECK (app_platform IN ('macos', 'ios')),
    payment_id VARCHAR(255),
    payment_provider VARCHAR(32),
    max_devices INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX idx_licenses_license_key ON licenses (license_key);
CREATE INDEX idx_licenses_status ON licenses (status);
CREATE INDEX idx_licenses_owner_email ON licenses (owner_email);

-- Prevent duplicate trial licenses per email at the database level
CREATE UNIQUE INDEX idx_licenses_one_trial_per_email
    ON licenses (owner_email) WHERE license_type = 'trial';

CREATE TABLE IF NOT EXISTS activations (
    id SERIAL PRIMARY KEY,
    license_id INTEGER NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
    machine_id VARCHAR(255) NOT NULL,
    machine_label VARCHAR(255),
    app_platform VARCHAR(16) CHECK (app_platform IN ('macos', 'ios')),
    app_version VARCHAR(32),
    activated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deactivated_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_activations_license_id ON activations (license_id);
CREATE INDEX idx_activations_machine_id ON activations (machine_id);
