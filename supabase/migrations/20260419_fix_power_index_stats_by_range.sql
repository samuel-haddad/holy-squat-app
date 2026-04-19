-- =============================================
-- Migration: Fix get_athlete_stats_by_range (COMPATIBILITY cb9ad79)
-- Changes:
--   1. USES Independent Subqueries - Zero dependencies
--   2. Units: Converts lbs to kg (x 0.453592) for Power Index
--   3. KEY FIX: 'exercise' instead of 'label' for best_evolution
--   4. Defaulting to 0 for missing data
-- =============================================

CREATE OR REPLACE FUNCTION public.get_athlete_stats_by_range(
  p_email      text,
  p_start_date date,
  p_end_date   date
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
AS $func$
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
          WITH stats AS (
            SELECT
              COALESCE(AVG(esforco), 0) AS media_semestre,
              COALESCE(AVG(esforco) FILTER (WHERE d_treino BETWEEN p_start_date AND p_end_date), 0) AS media_intervalo
            FROM (
              SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
              FROM public.workouts_logs
              WHERE user_email = p_email AND done = 1 AND workout_date >= p_end_date - INTERVAL '6 months'
              GROUP BY 1
            ) d
          )
          SELECT ROUND(((media_intervalo - media_semestre) / NULLIF(media_semestre, 0)) * 100, 1) FROM stats
        ), 0)
      ),
      
      'current_workload', COALESCE((
        SELECT ROUND(AVG(esforco), 1)
        FROM (
          SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
          FROM public.workouts_logs
          WHERE user_email = p_email AND done = 1 AND workout_date BETWEEN p_start_date AND p_end_date
          GROUP BY 1
        ) m
      ), 0),
      
      'weekly_freq', COALESCE((
        SELECT ROUND(COUNT(DISTINCT workout_date)::DECIMAL / NULLIF((p_end_date - p_start_date)::NUMERIC / 7.0, 0), 1)
        FROM public.workouts_logs
        WHERE user_email = p_email AND done = 1 AND workout_date BETWEEN p_start_date AND p_end_date
      ), 0),
      
      'streak', COALESCE((
        WITH weekly_counts AS (
          SELECT DATE_TRUNC('week', workout_date)::DATE AS week_start, COUNT(DISTINCT workout_date) AS days_trained
          FROM public.workouts_logs WHERE user_email = p_email AND done = 1 GROUP BY 1
        ),
        streak_calc AS (
          SELECT (CURRENT_DATE - week_start) / 7 AS weeks_ago FROM weekly_counts WHERE days_trained >= 3
        )
        SELECT COUNT(*) FROM (
          SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) AS rn FROM streak_calc WHERE weeks_ago <= 104
        ) s WHERE weeks_ago = rn - 1
      ), 0)
    ),
    
    'radar', COALESCE((
      SELECT jsonb_agg(radar_item)
      FROM (
        SELECT LEFT(w.exercise_type, 15) AS category, COUNT(wl.wod_exercise_id) AS count
        FROM public.workouts w
        LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id AND wl.done = 1
        WHERE w.user_email = p_email AND w.exercise_type NOT LIKE 'http%' AND length(w.exercise_type) > 1
          AND (w.date::DATE BETWEEN p_start_date AND p_end_date OR wl.workout_date BETWEEN p_start_date AND p_end_date)
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
$func$;
