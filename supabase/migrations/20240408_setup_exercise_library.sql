-- Enable the extension for similarity search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create the exercise library table
CREATE TABLE IF NOT EXISTS public.exercise_library (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    link TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create GIN index for fast search by trigrams (fuzzy search)
CREATE INDEX IF NOT EXISTS idx_exercise_library_name_trgm ON public.exercise_library USING GIN (name gin_trgm_ops);

-- RPC function to fetch the closest link based on the name
CREATE OR REPLACE FUNCTION get_closest_exercise_link(search_name TEXT)
RETURNS TEXT AS $$
    SELECT link 
    FROM public.exercise_library 
    WHERE similarity(name, search_name) > 0.5
    ORDER BY similarity(name, search_name) DESC 
    LIMIT 1;
$$ LANGUAGE sql STABLE;
