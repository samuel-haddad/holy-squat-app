-- =============================================
-- Migration: ai_generation_jobs table + orchestration trigger
-- Purpose: Background job queue for AI workout generation
-- =============================================

-- 1. Enable pg_net extension (async HTTP from SQL)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA net;

-- 2. Create job queue table
CREATE TABLE IF NOT EXISTS public.ai_generation_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) NOT NULL,
  user_email text NOT NULL,
  ai_coach_name text,
  job_type text NOT NULL CHECK (job_type IN ('new_plan', 'next_cycle')),
  current_step integer NOT NULL DEFAULT 1,
  total_steps integer NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'error')),
  input_params jsonb NOT NULL DEFAULT '{}',
  step_1_result jsonb,
  step_2_result jsonb,
  step_3_result jsonb,
  step_4_result jsonb,
  plan_id text,
  error_message text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 3. Row Level Security
ALTER TABLE public.ai_generation_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own jobs"
  ON public.ai_generation_jobs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own jobs"
  ON public.ai_generation_jobs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 4. Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE ai_generation_jobs;

-- 5. Trigger function: calls orchestrate-treino Edge Function via pg_net
-- IMPORTANT: Before running, store these secrets in Vault via Dashboard or SQL:
--   SELECT vault.create_secret('https://<project>.supabase.co', 'supabase_url');
--   SELECT vault.create_secret('eyJ...service_role_key...', 'service_role_key');
CREATE OR REPLACE FUNCTION public.trigger_orchestrate_next_step()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url text;
  _service_role_key text;
BEGIN
  SELECT decrypted_secret INTO _supabase_url
    FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1;

  SELECT decrypted_secret INTO _service_role_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF _supabase_url IS NULL OR _service_role_key IS NULL THEN
    RAISE WARNING 'Vault secrets not configured. Skipping orchestration.';
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := _supabase_url || '/functions/v1/orchestrate-treino',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _service_role_key
    ),
    body := jsonb_build_object('job_id', NEW.id::text)
  );

  RETURN NEW;
END;
$$;

-- 6. Trigger: fires on INSERT or when current_step changes (but not if completed/error)
CREATE TRIGGER on_job_step_change
AFTER INSERT OR UPDATE OF current_step ON public.ai_generation_jobs
FOR EACH ROW
WHEN (NEW.status NOT IN ('completed', 'error'))
EXECUTE FUNCTION public.trigger_orchestrate_next_step();
