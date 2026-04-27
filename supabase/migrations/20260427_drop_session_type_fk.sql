-- ============================================================
-- Drop the FK constraint between sessions.session_type → icons
--
-- Rationale: the AI Coach can generate any session_type from
-- a large vocabulary. Keeping a FK to the icons table causes
-- insert failures whenever a new type is introduced.
--
-- After this migration:
--  • sessions.session_type is a free-text field (no FK).
--  • Icons are looked up with a LEFT JOIN / .select('*, icons(img)')
--    which returns NULL img for unknown types — the Flutter app
--    already handles this gracefully with a fallback icon.
--  • The icons table is kept as a lookup table for known types.
-- ============================================================

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_session_type_fkey;
