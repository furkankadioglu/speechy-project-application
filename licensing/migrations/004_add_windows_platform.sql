-- Add Windows platform support to licensing database
ALTER TABLE licenses DROP CONSTRAINT IF EXISTS licenses_app_platform_check;
ALTER TABLE activations DROP CONSTRAINT IF EXISTS activations_app_platform_check;

-- Re-add with windows included
DO $$ BEGIN
    ALTER TABLE licenses ADD CONSTRAINT licenses_app_platform_check
        CHECK (app_platform IN ('macos', 'windows', 'ios'));
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE activations ADD CONSTRAINT activations_app_platform_check
        CHECK (app_platform IN ('macos', 'windows', 'ios'));
EXCEPTION WHEN others THEN NULL;
END $$;
