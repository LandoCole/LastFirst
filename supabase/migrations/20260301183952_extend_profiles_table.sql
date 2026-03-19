
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS user_taste_summary TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'America/Chicago';
;
