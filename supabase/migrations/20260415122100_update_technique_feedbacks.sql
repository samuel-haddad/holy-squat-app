-- Migration to add raw_video_path and improve technique_feedbacks table structure

-- 1. Finalize the table structure
ALTER TABLE public.technique_feedbacks 
ADD COLUMN IF NOT EXISTS raw_video_path TEXT;

-- 2. Add technical status for tracking (optional but recommended for UX)
ALTER TABLE public.technique_feedbacks 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed'));

-- 3. In production, you would set up a Database Webhook to trigger the Edge Function:
-- This can be done via the Supabase Dashboard -> Database -> Webhooks OR via SQL with pg_net.
-- Example of PG_NET trigger (requires extension):
/*
CREATE OR REPLACE TRIGGER trigger_process_technique
AFTER INSERT OR UPDATE OF raw_video_path ON public.technique_feedbacks
FOR EACH ROW
WHEN (NEW.raw_video_path IS NOT NULL AND (OLD.raw_video_path IS NULL OR NEW.raw_video_path <> OLD.raw_video_path))
EXECUTE FUNCTION public.trigger_edge_function('process-technique');
*/
