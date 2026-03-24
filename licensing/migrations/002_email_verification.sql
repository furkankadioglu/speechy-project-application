CREATE TABLE IF NOT EXISTS email_verifications (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    token VARCHAR(64) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    license_id INTEGER REFERENCES licenses(id) ON DELETE SET NULL
);

CREATE INDEX idx_email_verifications_token ON email_verifications (token);
CREATE INDEX idx_email_verifications_email ON email_verifications (email);
