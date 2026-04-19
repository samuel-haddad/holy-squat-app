-- =============================================
-- Migration: Fix get_athlete_stats_by_range (ULTRA-COMPATIBLE PLPGSQL)
-- Changes:
--   1. USES PLPGSQL for guaranteed single object return
--   2. Units: converts lb to kg (0.453592)
--   3. KEY FIX: 'exercise' instead of 'label' for best_evolution
--   4. Filtered by START and END date
-- =============================================

CREATE OR REPLACE FUNCTION public.get_athlete_stats_by_range(
  p_email      text,
  p_start_date date,
  p_end_date   date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  res_adherence        NUMERIC;
  res_power_index      NUMERIC;
  res_avg_pse          NUMERIC;
  res_evol_percent     NUMERIC;
  res_current_workload NUMERIC;
  res_weekly_freq      NUMERIC;
  res_streak           INTEGER;
  res_radar            JSONB;
  res_heatmap          JSONB;
  v_num_weeks          NUMERIC;
BEGIN
  -- Weeks in interval
  v_num_weeks := NULLIF((p_end_date - p_start_date)::NUMERIC / 7.0, 0);
  IF v_num_weeks IS NULL THEN v_num_weeks := 1; END IF;

  -- 1. Adherence (in range)
  SELECT COALESCE(
    ROUND(
      CASE WHEN COUNT(w.wod_exercise_id) > 0
           THEN (COUNT(wl.wod_exercise_id) FILTER (WHERE wl.done = 1))::DECIMAL
                / COUNT(w.wod_exercise_id)::DECIMAL * 100
           ELSE 0 END, 1), 0)
  INTO res_adherence
  FROM public.workouts w
  LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
  WHERE w.user_email = p_email AND w.date IS NOT NULL AND w.date::DATE BETWEEN p_start_date AND p_end_date;

  -- 2. Power Index (global)
  SELECT COALESCE(
    ROUND(SUM(
      CASE
        WHEN LOWER(TRIM(COALESCE(pr_unit, ''))) IN ('lb', 'lbs', 'libra', 'libras')
        THEN CAST(NULLIF(pr, '') AS NUMERIC) * 0.453592
        ELSE CAST(NULLIF(pr, '') AS NUMERIC)
      END
    ), 0), 0)
  INTO res_power_index
  FROM public.pr_log
  WHERE user_email = p_email AND pr IS NOT NULL AND pr != '';

  -- 3. Avg PSE (in range)
  SELECT COALESCE(ROUND(AVG(NULLIF(pse, '')::DECIMAL), 1), 0)
  INTO res_avg_pse
  FROM public.workouts_logs
  WHERE user_email = p_email AND done = 1 AND pse IS NOT NULL AND pse != '' 
    AND workout_date BETWEEN p_start_date AND p_end_date;

  -- 4. Evolution
  WITH daily_stats AS (
    SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
    FROM public.workouts_logs
    WHERE user_email = p_email AND done = 1 AND workout_date >= p_end_date - INTERVAL '6 months'
    GROUP BY 1
  ),
  stats_agg AS (
    SELECT
      COALESCE(AVG(esforco), 0) AS m_semestre,
      COALESCE(AVG(esforco) FILTER (WHERE d_treino BETWEEN p_start_date AND p_end_date), 0) AS m_intervalo
    FROM daily_stats
  )
  SELECT ROUND(((m_intervalo - m_semestre) / NULLIF(m_semestre, 0)) * 100, 1) INTO res_evol_percent FROM stats_agg;

  -- 5. Workload (in range)
  SELECT COALESCE(ROUND(AVG(esforco), 1), 0) INTO res_current_workload
  FROM (
    SELECT workout_date::DATE AS d_treino, SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) AS esforco
    FROM public.workouts_logs
    WHERE user_email = p_email AND done = 1 AND workout_date BETWEEN p_start_date AND p_end_date
    GROUP BY 1
  ) _sub_workload;

  -- 6. Weekly Freq (normalized by range)
  SELECT COALESCE(ROUND(COUNT(DISTINCT workout_date)::DECIMAL / v_num_weeks, 1), 0)
  INTO res_weekly_freq
  FROM public.workouts_logs
  WHERE user_email = p_email AND done = 1 AND workout_date BETWEEN p_start_date AND p_end_date;

  -- 7. Streak
  WITH weekly_counts AS (
    SELECT DATE_TRUNC('week', workout_date)::DATE AS week_start, COUNT(DISTINCT workout_date) AS days_trained
    FROM public.workouts_logs WHERE user_email = p_email AND done = 1 GROUP BY 1
  ),
  streak_calc AS (
    SELECT (CURRENT_DATE - week_start) / 7 AS weeks_ago FROM weekly_counts WHERE days_trained >= 3
  )
  SELECT COALESCE(COUNT(*), 0) INTO res_streak FROM (
    SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) AS rn FROM streak_calc WHERE weeks_ago <= 104
  ) s WHERE weeks_ago = rn - 1;

  -- 8. Radar (in range)
  SELECT COALESCE(jsonb_agg(radar_item), '[]'::jsonb) INTO res_radar
  FROM (
    SELECT LEFT(w.exercise_type, 15) AS category, COUNT(wl.wod_exercise_id) AS count
    FROM public.workouts w
    LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id AND wl.done = 1
    WHERE w.user_email = p_email AND w.exercise_type NOT LIKE 'http%' AND length(w.exercise_type) > 1
      AND (w.date::DATE BETWEEN p_start_date AND p_end_date OR wl.workout_date BETWEEN p_start_date AND p_end_date)
    GROUP BY 1 ORDER BY count DESC LIMIT 5
  ) radar_item;

  -- 9. Heatmap (in range)
  SELECT COALESCE(jsonb_agg(heatmap_item), '[]'::jsonb) INTO res_heatmap
  FROM (
    SELECT workout_date::DATE AS date, COUNT(*) FILTER (WHERE done = 1) AS count, MAX(COALESCE(NULLIF(pse, '')::DECIMAL, 0)) AS intensity
    FROM public.workouts_logs WHERE user_email = p_email AND workout_date BETWEEN p_start_date AND p_end_date
    GROUP BY 1 ORDER BY 1 ASC
  ) heatmap_item;

  RETURN jsonb_build_object(
    'kpis', jsonb_build_object(
      'adherence', COALESCE(res_adherence, 0),
      'power_index', COALESCE(res_power_index, 0),
      'avg_pse', COALESCE(res_avg_pse, 0),
      'best_evolution', jsonb_build_object(
        'exercise', 'Esforço Global',
        'percent', COALESCE(res_evol_percent, 0)
      ),
      'current_workload', COALESCE(res_current_workload, 0),
      'weekly_freq', COALESCE(res_weekly_freq, 0),
      'streak', COALESCE(res_streak, 0)
    ),
    'radar', res_radar,
    'heatmap', res_heatmap
  );
END;
$$;
