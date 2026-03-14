ALTER TABLE email_verifications ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45);
CREATE INDEX IF NOT EXISTS idx_email_verifications_ip_recent ON email_verifications (ip_address, created_at);
