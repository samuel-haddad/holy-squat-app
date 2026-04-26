-- =============================================
-- Migration: Update IFR (Índice de Força Relativa) Logic
-- Modifies get_athlete_planning_stats and get_athlete_stats_by_range
-- to calculate IFR based on workouts and workouts_logs instead of pr_log.
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
        WHERE w.user_email = p_email AND w.date IS NOT NULL AND w.date::DATE >= CURRENT_DATE - INTERVAL '30 days'
      ), 0),
      
      -- AJUSTE: IFR usando os melhores resultados nos treinos dos últimos 6 meses
      'ifr', COALESCE((
        SELECT ROUND(
          (SUM(max_recent_weight_kg) / NULLIF(p_user_weight, 0))::NUMERIC, 2)
        FROM (
          SELECT 
            w.exercise,
            MAX(
              CASE
                WHEN wl.weight IS NULL OR wl.weight::text = '' THEN 0
                WHEN LOWER(TRIM(COALESCE(wl.weight_unit, ''))) IN ('lb', 'lbs', 'libra', 'libras')
                THEN (CASE WHEN wl.weight::text ~ '^[0-9]+(\.[0-9]+)?$' THEN wl.weight::text::numeric ELSE 0 END) * 0.453592
                ELSE (CASE WHEN wl.weight::text ~ '^[0-9]+(\.[0-9]+)?$' THEN wl.weight::text::numeric ELSE 0 END)
              END
            ) as max_recent_weight_kg
          FROM public.workouts w
          INNER JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
          WHERE w.user_email = p_email 
            AND wl.done = 1
            AND wl.weight IS NOT NULL AND wl.weight::text != ''
            AND wl.workout_date >= CURRENT_DATE - INTERVAL '6 months'
            AND (
              w.exercise ILIKE '%back squat%' OR
              w.exercise ILIKE '%deadlift%' OR
              w.exercise ILIKE '%shoulder press%' OR
              w.exercise ILIKE '%strict press%' OR
              w.exercise ILIKE '%overhead press%'
            )
          GROUP BY w.exercise
        ) _best_recent
      ), 0),
      
      'avg_pse', COALESCE((
        SELECT ROUND(AVG(pse_val), 1)
        FROM (
          SELECT NULLIF(pse, '')::DECIMAL AS pse_val
          FROM public.workouts_logs
          WHERE user_email = p_email AND done = 1 AND pse IS NOT NULL AND pse != ''
          ORDER BY workout_date DESC LIMIT 10
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
              SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
              FROM public.workouts_logs
              WHERE user_email = p_email AND done = 1 AND workout_date >= CURRENT_DATE - INTERVAL '6 months'
              GROUP BY 1
            ) _daily
          ) _stats
        ), 0)
      ),
      
      'current_workload', COALESCE((
        SELECT ROUND(AVG(esforco), 1)
        FROM (
          SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
          FROM public.workouts_logs
          WHERE user_email = p_email AND done = 1 AND workout_date >= CURRENT_DATE - INTERVAL '30 days'
          GROUP BY 1
        ) _workload
      ), 0),
      
      'weekly_freq', COALESCE((
        SELECT ROUND(COUNT(DISTINCT workout_date)::DECIMAL / 4.0, 1)
        FROM public.workouts_logs
        WHERE user_email = p_email AND done = 1 AND workout_date >= CURRENT_DATE - INTERVAL '28 days'
      ), 0),
      
      'streak', COALESCE((
        SELECT COUNT(*) FROM (
          SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) AS rn 
          FROM (
            SELECT (CURRENT_DATE - DATE_TRUNC('week', workout_date)::DATE) / 7 AS weeks_ago 
            FROM public.workouts_logs 
            WHERE user_email = p_email AND done = 1 
            GROUP BY 1 HAVING COUNT(DISTINCT workout_date) >= 3
          ) _streak_calc WHERE weeks_ago <= 104
        ) _streak_rn WHERE weeks_ago = rn - 1
      ), 0)
    ),
    
    'radar', COALESCE((
      SELECT jsonb_agg(radar_item)
      FROM (
        SELECT LEFT(exercise_type, 15) AS category, COUNT(*) AS count
        FROM public.workouts
        WHERE user_email = p_email AND exercise_type NOT LIKE 'http%' AND length(exercise_type) > 1
          AND date::DATE >= CURRENT_DATE - INTERVAL '90 days'
        GROUP BY 1 ORDER BY count DESC LIMIT 5
      ) radar_item
    ), '[]'::jsonb),
    
    'heatmap', COALESCE((
      SELECT jsonb_agg(heatmap_item)
      FROM (
        SELECT workout_date::DATE AS date, COUNT(*) FILTER (WHERE done = 1) AS count, MAX(COALESCE(NULLIF(pse, '')::DECIMAL, 0)) AS intensity
        FROM public.workouts_logs WHERE user_email = p_email AND workout_date >= CURRENT_DATE - INTERVAL '6 months'
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
      ), 0),
      
      -- AJUSTE: IFR usando os melhores resultados nos treinos no intervalo de tempo
      'ifr', COALESCE((
        SELECT ROUND(
          (SUM(max_recent_weight_kg) / NULLIF(p_user_weight, 0))::NUMERIC, 2)
        FROM (
          SELECT 
            w.exercise,
            MAX(
              CASE
                WHEN wl.weight IS NULL OR wl.weight::text = '' THEN 0
                WHEN LOWER(TRIM(COALESCE(wl.weight_unit, ''))) IN ('lb', 'lbs', 'libra', 'libras')
                THEN (CASE WHEN wl.weight::text ~ '^[0-9]+(\.[0-9]+)?$' THEN wl.weight::text::numeric ELSE 0 END) * 0.453592
                ELSE (CASE WHEN wl.weight::text ~ '^[0-9]+(\.[0-9]+)?$' THEN wl.weight::text::numeric ELSE 0 END)
              END
            ) as max_recent_weight_kg
          FROM public.workouts w
          INNER JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
          WHERE w.user_email = p_email 
            AND wl.done = 1
            AND wl.weight IS NOT NULL AND wl.weight::text != ''
            AND wl.workout_date BETWEEN p_start_date AND p_end_date
            AND (
              w.exercise ILIKE '%back squat%' OR
              w.exercise ILIKE '%deadlift%' OR
              w.exercise ILIKE '%shoulder press%' OR
              w.exercise ILIKE '%strict press%' OR
              w.exercise ILIKE '%overhead press%'
            )
          GROUP BY w.exercise
        ) _best_recent
      ), 0),
      
      'avg_pse', COALESCE((
        SELECT ROUND(AVG(NULLIF(pse, '')::DECIMAL), 1)
        FROM public.workouts_logs
        WHERE user_email = p_email AND done = 1 AND pse IS NOT NULL AND pse != '' 
          AND workout_date BETWEEN p_start_date AND p_end_date
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
              SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
              FROM public.workouts_logs
              WHERE user_email = p_email AND done = 1 AND workout_date >= p_end_date - INTERVAL '6 months'
              GROUP BY 1
            ) _daily
          ) _stats
        ), 0)
      ),
      
      'current_workload', COALESCE((
        SELECT ROUND(AVG(esforco), 1)
        FROM (
          SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
          FROM public.workouts_logs
          WHERE user_email = p_email AND done = 1 AND workout_date BETWEEN p_start_date AND p_end_date
          GROUP BY 1
        ) _workload
      ), 0),
      
      'weekly_freq', COALESCE((
        SELECT ROUND(COUNT(DISTINCT workout_date)::DECIMAL / NULLIF((p_end_date - p_start_date)::NUMERIC / 7.0, 0), 1)
        FROM public.workouts_logs
        WHERE user_email = p_email AND done = 1 AND workout_date BETWEEN p_start_date AND p_end_date
      ), 0),
      
      'streak', COALESCE((
        SELECT COUNT(*) FROM (
          SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) AS rn 
          FROM (
            SELECT (CURRENT_DATE - DATE_TRUNC('week', workout_date)::DATE) / 7 AS weeks_ago 
            FROM public.workouts_logs 
            WHERE user_email = p_email AND done = 1 
            GROUP BY 1 HAVING COUNT(DISTINCT workout_date) >= 3
          ) _streak_calc WHERE weeks_ago <= 104
        ) _streak_rn WHERE weeks_ago = rn - 1
      ), 0)
    ),
    
    'radar', COALESCE((
      SELECT jsonb_agg(radar_item)
      FROM (
        SELECT LEFT(exercise_type, 15) AS category, COUNT(*) AS count
        FROM public.workouts
        WHERE user_email = p_email AND exercise_type NOT LIKE 'http%' AND length(exercise_type) > 1
          AND date::DATE BETWEEN p_start_date AND p_end_date
        GROUP BY 1 ORDER BY count DESC LIMIT 5
      ) radar_item
    ), '[]'::jsonb),
    
    'heatmap', COALESCE((
      SELECT jsonb_agg(heatmap_item)
      FROM (
        SELECT workout_date::DATE AS date, COUNT(*) FILTER (WHERE done = 1) AS count, MAX(COALESCE(NULLIF(pse, '')::DECIMAL, 0)) AS intensity
        FROM public.workouts_logs WHERE user_email = p_email AND workout_date BETWEEN p_start_date AND p_end_date
        GROUP BY 1 ORDER BY 1 ASC
      ) heatmap_item
    ), '[]'::jsonb)
  );
$$;
