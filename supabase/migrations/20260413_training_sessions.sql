-- Training Sessions: structured per-session availability for each athlete
CREATE TABLE IF NOT EXISTS public.training_sessions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    session_number INT NOT NULL,
    locations TEXT[] NOT NULL DEFAULT '{}',
    duration_minutes INT NOT NULL DEFAULT 60,
    schedule TEXT[] NOT NULL DEFAULT '{}',
    time_of_day TEXT NOT NULL DEFAULT 'morning',
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, session_number)
);

-- Row Level Security
ALTER TABLE public.training_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own training sessions"
    ON public.training_sessions
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION update_training_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_training_sessions_updated_at
    BEFORE UPDATE ON public.training_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_training_sessions_updated_at();
