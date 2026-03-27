-- Migration 005: App version management
-- Stores latest and minimum acceptable versions per platform.

CREATE TABLE IF NOT EXISTS app_versions (
    id              SERIAL PRIMARY KEY,
    platform        VARCHAR(16)  NOT NULL UNIQUE,  -- macos | windows | ios
    latest_version  VARCHAR(32)  NOT NULL DEFAULT '1.0.0',
    minimum_version VARCHAR(32)  NOT NULL DEFAULT '1.0.0',
    update_url      TEXT,
    notes           TEXT,
    updated_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Seed default rows for each platform
INSERT INTO app_versions (platform, latest_version, minimum_version, update_url)
VALUES
    ('macos',   '1.0.0', '1.0.0', 'https://speechy.frkn.com.tr'),
    ('windows', '1.0.0', '1.0.0', 'https://speechy.frkn.com.tr'),
    ('ios',     '1.0.0', '1.0.0', 'https://speechy.frkn.com.tr')
ON CONFLICT (platform) DO NOTHING;
