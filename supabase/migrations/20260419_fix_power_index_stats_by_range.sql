-- =============================================
-- Migration: Fix get_athlete_stats_by_range (NAKED SELECT VERSION - NO VARIABLES)
-- This version eliminates all variables to bypass the Supabase SQL Editor parser bug (42P01).
-- Compatible with commit cb9ad79 (uses 'exercise' key).
-- =============================================

CREATE OR REPLACE FUNCTION public.get_athlete_stats_by_range(
  p_email      text,
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
      
      'power_index', COALESCE((
        SELECT ROUND(SUM(
          CASE
            WHEN LOWER(TRIM(COALESCE(pr_unit, ''))) IN ('lb', 'lbs', 'libra', 'libras')
            THEN CAST(NULLIF(pr, '') AS NUMERIC) * 0.453592
            ELSE CAST(NULLIF(pr, '') AS NUMERIC)
          END
        ), 0)
        FROM public.pr_log
        WHERE user_email = p_email AND pr IS NOT NULL AND pr != ''
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
