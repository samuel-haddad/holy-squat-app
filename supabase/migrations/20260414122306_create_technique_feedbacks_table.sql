-- Migration for Technique feature: Feedbacks table and Storage bucket

-- 1. Create the technique_feedbacks table
CREATE TABLE IF NOT EXISTS public.technique_feedbacks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    exercise_name TEXT NOT NULL,
    processed_video_path TEXT,
    resume_text TEXT,
    improve_exercises JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 2. Add an index to speed up lookup by user and exercise
CREATE INDEX IF NOT EXISTS idx_technique_feedbacks_user_exercise ON public.technique_feedbacks(user_id, exercise_name);

-- 3. In the new logical map, we will use UPSERT or periodic cleanup to maintain only the latest feedback.
-- However, we can create a unique constraint in case we want to strictly use Postgres UPSERTs
-- UNIQUE CONSTRAINT ON (user_id, exercise_name) guarantees only 1 row per exercise per user
ALTER TABLE public.technique_feedbacks ADD CONSTRAINT technique_feedbacks_user_exercise_key UNIQUE (user_id, exercise_name);

-- 4. Set up Row Level Security (RLS)
ALTER TABLE public.technique_feedbacks ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own feedbacks
CREATE POLICY "Users can view their own technique feedbacks" 
ON public.technique_feedbacks FOR SELECT 
USING (auth.uid() = user_id);

-- Allow users to insert their own feedbacks
CREATE POLICY "Users can insert their own technique feedbacks" 
ON public.technique_feedbacks FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own feedbacks
CREATE POLICY "Users can update their own technique feedbacks" 
ON public.technique_feedbacks FOR UPDATE 
USING (auth.uid() = user_id);

-- Allow users to delete their own feedbacks
CREATE POLICY "Users can delete their own technique feedbacks" 
ON public.technique_feedbacks FOR DELETE 
USING (auth.uid() = user_id);


-- 5. Storage setup for the videos
INSERT INTO storage.buckets (id, name, public) 
VALUES ('technique_videos', 'technique_videos', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
CREATE POLICY "Users can upload raw technique videos" 
ON storage.objects FOR INSERT 
WITH CHECK (
  bucket_id = 'technique_videos' AND 
  auth.uid() = owner AND
  (storage.foldername(name))[1] = 'raw'
);

CREATE POLICY "Users can view their own technique videos" 
ON storage.objects FOR SELECT 
USING (
  bucket_id = 'technique_videos' AND 
  auth.uid() = owner
);

CREATE POLICY "Users can delete their own technique videos" 
ON storage.objects FOR DELETE 
USING (
  bucket_id = 'technique_videos' AND 
  auth.uid() = owner
);
