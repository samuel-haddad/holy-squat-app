-- Migration to cleanup unnecessary profile fields from Skills & Training section
-- Preserving anamnesis and migrating it conceptually to the 'About' section

ALTER TABLE profiles 
DROP COLUMN IF EXISTS active_hours_value,
DROP COLUMN IF EXISTS active_hours_unit,
DROP COLUMN IF EXISTS sessions_per_day,
DROP COLUMN IF EXISTS where_train,
DROP COLUMN IF EXISTS additional_info,
DROP COLUMN IF EXISTS background_file_url;
