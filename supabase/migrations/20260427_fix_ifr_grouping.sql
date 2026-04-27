-- =============================================
-- Migration: Fix IFR Grouping Logic
-- Agrupa variações de nomes de exercícios em categorias (Squat, Deadlift, Press)
-- para garantir que apenas o melhor resultado de cada categoria seja somado,
-- evitando duplicidade por nomes como "Aquecimento", "Strict", etc.
-- =============================================

-- 1. Update get_athlete_planning_stats
CREATE OR REPLACE FUNCTION public.get_athlete_planning_stats(p_email text, p_user_weight numeric)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
AS $$
SELECT jsonb_build_object(
    'kpis', jsonb_build_object(
      'adherence', COALESCE((
        SELECT ROUND(
          CASE WHEN COUNT(w.wod_exercise_id) > 0
               THEN (COUNT(wl.wod_exercise_id) FILTER (WHERE wl.done = 1))::DECIMAL
                    / COUNT(w.wod_exercise_id)::DECIMAL * 100
               ELSE 0 END, 1)
        FROM public.workouts w
        LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE w.user_email = p_email 
          AND w.date IS NOT NULL 
          AND w.date::DATE >= CURRENT_DATE - INTERVAL '180 days'
          AND w.session_type NOT ILIKE '%descanso%'
      ), 0),
      
      'ifr', COALESCE((
        SELECT ROUND(
          (SUM(max_recent_weight_kg) / NULLIF(p_user_weight, 0))::NUMERIC, 2)
        FROM (
          SELECT 
            CASE 
              WHEN w.exercise ILIKE '%back squat%' THEN 'Back Squat'
              WHEN w.exercise ILIKE '%deadlift%' THEN 'Deadlift'
              WHEN w.exercise ILIKE '%shoulder press%' OR w.exercise ILIKE '%strict press%' 
                OR w.exercise ILIKE '%overhead press%' OR w.exercise ILIKE '%push press%' THEN 'Press'
            END as category,
            MAX(
              CASE
                WHEN wl.weight IS NULL OR wl.weight::text = '' THEN 0
                WHEN LOWER(TRIM(COALESCE(wl.weight_unit, ''))) IN ('lb', 'lbs', 'libra', 'libras')
                THEN (CASE WHEN wl.weight::text ~ '[0-9]' THEN (SUBSTRING(wl.weight::text FROM '([0-9]+[.]?[0-9]*)'))::numeric ELSE 0 END) * 0.453592
                ELSE (CASE WHEN wl.weight::text ~ '[0-9]' THEN (SUBSTRING(wl.weight::text FROM '([0-9]+[.]?[0-9]*)'))::numeric ELSE 0 END)
              END
            ) as max_recent_weight_kg
          FROM public.workouts w
          INNER JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
          WHERE w.user_email = p_email 
            AND wl.done = 1
            AND wl.weight IS NOT NULL AND wl.weight::text != ''
            AND wl.workout_date >= CURRENT_DATE - INTERVAL '180 days'
            AND w.session_type NOT ILIKE '%descanso%'
            AND (
              w.exercise ILIKE '%back squat%' OR
              w.exercise ILIKE '%deadlift%' OR
              w.exercise ILIKE '%shoulder press%' OR
              w.exercise ILIKE '%strict press%' OR
              w.exercise ILIKE '%overhead press%' OR
              w.exercise ILIKE '%push press%'
            )
          GROUP BY 1 -- Agrupa pela categoria definida no CASE
        ) _best_recent
      ), 0),
      
      'avg_pse', COALESCE((
        SELECT ROUND(AVG(pse_val), 1)
        FROM (
          SELECT NULLIF(wl.pse, '')::DECIMAL AS pse_val
          FROM public.workouts_logs wl
          INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
          WHERE wl.user_email = p_email AND wl.done = 1 AND wl.pse IS NOT NULL AND wl.pse != ''
            AND wl.workout_date >= CURRENT_DATE - INTERVAL '180 days'
            AND w.session_type NOT ILIKE '%descanso%'
        ) _sub
      ), 0),
      
      'best_evolution', jsonb_build_object(
        'exercise', 'Esforço Global',
        'percent', COALESCE((
          SELECT ROUND(((media_mes - media_semestre) / NULLIF(media_semestre, 0)) * 100, 1)
          FROM (
            SELECT
              AVG(esforco) AS media_semestre,
              AVG(esforco) FILTER (WHERE d_treino >= CURRENT_DATE - INTERVAL '30 days') AS media_mes
            FROM (
              SELECT wl.workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(wl.pse, '')::DECIMAL, 1) * 10) AS esforco
              FROM public.workouts_logs wl
              INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
              WHERE wl.user_email = p_email AND wl.done = 1 AND wl.workout_date >= CURRENT_DATE - INTERVAL '180 days'
                AND w.session_type NOT ILIKE '%descanso%'
              GROUP BY 1
            ) _daily
          ) _stats
        ), 0)
      ),
      
      'weekly_freq', COALESCE((
        SELECT ROUND(COUNT(DISTINCT wl.workout_date)::DECIMAL / 26.0, 1)
        FROM public.workouts_logs wl
        INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE wl.user_email = p_email AND wl.done = 1 AND wl.workout_date >= CURRENT_DATE - INTERVAL '180 days'
          AND w.session_type NOT ILIKE '%descanso%'
      ), 0),
      
      'streak', COALESCE((
        SELECT COUNT(*) FROM (
          SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) AS rn 
          FROM (
            SELECT (CURRENT_DATE - DATE_TRUNC('week', wl.workout_date)::DATE) / 7 AS weeks_ago 
            FROM public.workouts_logs wl
            INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
            WHERE wl.user_email = p_email AND wl.done = 1 
              AND w.session_type NOT ILIKE '%descanso%'
            GROUP BY 1 HAVING COUNT(DISTINCT wl.workout_date) >= 3
          ) _streak_calc WHERE weeks_ago <= 104
        ) _streak_rn WHERE weeks_ago = rn - 1
      ), 0)
    ),
    
    'radar', COALESCE((
      SELECT jsonb_agg(radar_item)
      FROM (
        SELECT LEFT(w.exercise_type, 15) AS category, COUNT(*) AS count
        FROM public.workouts w
        WHERE w.user_email = p_email AND w.exercise_type NOT LIKE 'http%' AND length(w.exercise_type) > 1
          AND w.date::DATE >= CURRENT_DATE - INTERVAL '90 days'
          AND w.session_type NOT ILIKE '%descanso%'
        GROUP BY 1 ORDER BY count DESC LIMIT 5
      ) radar_item
    ), '[]'::jsonb),
    
    'heatmap', COALESCE((
      SELECT jsonb_agg(heatmap_item)
      FROM (
        SELECT wl.workout_date::DATE AS date, COUNT(*) FILTER (WHERE wl.done = 1) AS count, MAX(COALESCE(NULLIF(wl.pse, '')::DECIMAL, 0)) AS intensity
        FROM public.workouts_logs wl 
        INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE wl.user_email = p_email AND wl.workout_date >= CURRENT_DATE - INTERVAL '180 days'
          AND w.session_type NOT ILIKE '%descanso%'
        GROUP BY 1 ORDER BY 1 ASC
      ) heatmap_item
    ), '[]'::jsonb)
  );
$$;

-- 2. Update get_athlete_stats_by_range
CREATE OR REPLACE FUNCTION public.get_athlete_stats_by_range(
  p_email      text,
  p_user_weight numeric,
  p_start_date date,
  p_end_date   date
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT jsonb_build_object(
    'kpis', jsonb_build_object(
      'adherence', COALESCE((
        SELECT ROUND(
          CASE WHEN COUNT(w.wod_exercise_id) > 0
               THEN (COUNT(wl.wod_exercise_id) FILTER (WHERE wl.done = 1))::DECIMAL
                    / COUNT(w.wod_exercise_id)::DECIMAL * 100
               ELSE 0 END, 1)
        FROM public.workouts w
        LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE w.user_email = p_email AND w.date IS NOT NULL AND w.date::DATE BETWEEN p_start_date AND p_end_date
          AND w.session_type NOT ILIKE '%descanso%'
      ), 0),
      
      'ifr', COALESCE((
        SELECT ROUND(
          (SUM(max_recent_weight_kg) / NULLIF(p_user_weight, 0))::NUMERIC, 2)
        FROM (
          SELECT 
            CASE 
              WHEN w.exercise ILIKE '%back squat%' THEN 'Back Squat'
              WHEN w.exercise ILIKE '%deadlift%' THEN 'Deadlift'
              WHEN w.exercise ILIKE '%shoulder press%' OR w.exercise ILIKE '%strict press%' 
                OR w.exercise ILIKE '%overhead press%' OR w.exercise ILIKE '%push press%' THEN 'Press'
            END as category,
            MAX(
              CASE
                WHEN wl.weight IS NULL OR wl.weight::text = '' THEN 0
                WHEN LOWER(TRIM(COALESCE(wl.weight_unit, ''))) IN ('lb', 'lbs', 'libra', 'libras')
                THEN (CASE WHEN wl.weight::text ~ '[0-9]' THEN (SUBSTRING(wl.weight::text FROM '([0-9]+[.]?[0-9]*)'))::numeric ELSE 0 END) * 0.453592
                ELSE (CASE WHEN wl.weight::text ~ '[0-9]' THEN (SUBSTRING(wl.weight::text FROM '([0-9]+[.]?[0-9]*)'))::numeric ELSE 0 END)
              END
            ) as max_recent_weight_kg
          FROM public.workouts w
          INNER JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
          WHERE w.user_email = p_email 
            AND wl.done = 1
            AND wl.weight IS NOT NULL AND wl.weight::text != ''
            AND wl.workout_date BETWEEN p_start_date AND p_end_date
            AND w.session_type NOT ILIKE '%descanso%'
            AND (
              w.exercise ILIKE '%back squat%' OR
              w.exercise ILIKE '%deadlift%' OR
              w.exercise ILIKE '%shoulder press%' OR
              w.exercise ILIKE '%strict press%' OR
              w.exercise ILIKE '%overhead press%' OR
              w.exercise ILIKE '%push press%'
            )
          GROUP BY 1
        ) _best_recent
      ), 0),
      
      'avg_pse', COALESCE((
        SELECT ROUND(AVG(NULLIF(wl.pse, '')::DECIMAL), 1)
        FROM public.workouts_logs wl
        INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE wl.user_email = p_email AND wl.done = 1 AND wl.pse IS NOT NULL AND wl.pse != '' 
          AND wl.workout_date BETWEEN p_start_date AND p_end_date
          AND w.session_type NOT ILIKE '%descanso%'
      ), 0),
      
      'best_evolution', jsonb_build_object(
        'exercise', 'Esforço Global',
        'percent', COALESCE((
          SELECT ROUND(((media_intervalo - media_semestre) / NULLIF(media_semestre, 0)) * 100, 1)
          FROM (
            SELECT
              AVG(esforco) AS media_semestre,
              AVG(esforco) FILTER (WHERE d_treino BETWEEN p_start_date AND p_end_date) AS media_intervalo
            FROM (
              SELECT wl.workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(wl.pse, '')::DECIMAL, 1) * 10) AS esforco
              FROM public.workouts_logs wl
              INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
              WHERE wl.user_email = p_email AND wl.done = 1 AND wl.workout_date >= p_end_date - INTERVAL '6 months'
                AND w.session_type NOT ILIKE '%descanso%'
              GROUP BY 1
            ) _daily
          ) _stats
        ), 0)
      ),
      
      'weekly_freq', COALESCE((
        SELECT ROUND(COUNT(DISTINCT wl.workout_date)::DECIMAL / NULLIF((p_end_date - p_start_date)::NUMERIC / 7.0, 0), 1)
        FROM public.workouts_logs wl
        INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE wl.user_email = p_email AND wl.done = 1 AND wl.workout_date BETWEEN p_start_date AND p_end_date
          AND w.session_type NOT ILIKE '%descanso%'
      ), 0),
      
      'streak', COALESCE((
        SELECT COUNT(*) FROM (
          SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) AS rn 
          FROM (
            SELECT (CURRENT_DATE - DATE_TRUNC('week', wl.workout_date)::DATE) / 7 AS weeks_ago 
            FROM public.workouts_logs wl 
            INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
            WHERE wl.user_email = p_email AND wl.done = 1 
              AND w.session_type NOT ILIKE '%descanso%'
            GROUP BY 1 HAVING COUNT(DISTINCT wl.workout_date) >= 3
          ) _streak_calc WHERE weeks_ago <= 104
        ) _streak_rn WHERE weeks_ago = rn - 1
      ), 0)
    ),
    
    'radar', COALESCE((
      SELECT jsonb_agg(radar_item)
      FROM (
        SELECT LEFT(w.exercise_type, 15) AS category, COUNT(*) AS count
        FROM public.workouts w
        WHERE w.user_email = p_email AND w.exercise_type NOT LIKE 'http%' AND length(w.exercise_type) > 1
          AND w.date::DATE BETWEEN p_start_date AND p_end_date
          AND w.session_type NOT ILIKE '%descanso%'
        GROUP BY 1 ORDER BY count DESC LIMIT 5
      ) radar_item
    ), '[]'::jsonb),
    
    'heatmap', COALESCE((
      SELECT jsonb_agg(heatmap_item)
      FROM (
        SELECT wl.workout_date::DATE AS date, COUNT(*) FILTER (WHERE wl.done = 1) AS count, MAX(COALESCE(NULLIF(wl.pse, '')::DECIMAL, 0)) AS intensity
        FROM public.workouts_logs wl 
        INNER JOIN public.workouts w ON w.wod_exercise_id = wl.wod_exercise_id
        WHERE wl.user_email = p_email AND wl.workout_date BETWEEN p_start_date AND p_end_date
          AND w.session_type NOT ILIKE '%descanso%'
        GROUP BY 1 ORDER BY 1 ASC
      ) heatmap_item
    ), '[]'::jsonb)
  );
$$;
