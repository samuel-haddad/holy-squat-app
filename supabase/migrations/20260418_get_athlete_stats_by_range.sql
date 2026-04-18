-- =============================================
-- Migration: get_athlete_stats_by_range RPC
-- Purpose: Calculate athlete performance metrics for a specific date range
-- =============================================

CREATE OR REPLACE FUNCTION public.get_athlete_stats_by_range(
  p_email text,
  p_start_date date,
  p_end_date date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSONB; 
  v_adherence DECIMAL; 
  v_power_index DECIMAL; 
  v_radar_data JSONB; 
  v_heatmap_data JSONB;
  v_esforco_atual DECIMAL;
  v_evolucao_percent DECIMAL;
  v_weekly_freq DECIMAL;
  v_streak_weeks INTEGER;
  v_avg_pse DECIMAL;
  v_num_weeks DECIMAL;
BEGIN
  -- Calcular número de semanas no intervalo para normalização
  v_num_weeks := NULLIF((p_end_date - p_start_date)::DECIMAL / 7.0, 0);
  IF v_num_weeks IS NULL THEN v_num_weeks := 1; END IF;

  -- 1. Cálculo de Aderência (no intervalo)
  SELECT 
    CASE WHEN COUNT(w.wod_exercise_id) > 0 
         THEN (COUNT(wl.wod_exercise_id) FILTER (WHERE wl.done = 1)::DECIMAL / COUNT(w.wod_exercise_id)::DECIMAL) * 100 
         ELSE 0 END
  INTO v_adherence
  FROM public.workouts w
  LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id
  WHERE w.user_email = p_email
    AND w."date" IS NOT NULL
    AND w."date"::DATE BETWEEN p_start_date AND p_end_date;

  -- 2. Power Index (Soma de PRs de força) - Mantido Global como solicitado
  SELECT COALESCE(SUM(CAST(NULLIF(pr, '') AS NUMERIC)), 0) INTO v_power_index
  FROM public.pr_log 
  WHERE user_email = p_email AND pr != '' AND pr IS NOT NULL
    AND exercise IN ('Back Squat', 'Deadlift', 'Shoulder Press', 'Strict Press', 'Overhead Press');

  -- 3. Média de PSE (no intervalo)
  SELECT AVG(NULLIF(pse, '')::DECIMAL) INTO v_avg_pse
  FROM public.workouts_logs
  WHERE user_email = p_email 
    AND done = 1 
    AND pse IS NOT NULL 
    AND pse != ''
    AND workout_date BETWEEN p_start_date AND p_end_date;

  -- 4. Índice de Esforço Acumulado e Evolução
  WITH daily_stats AS (
      SELECT 
          workout_date::DATE as data_treino,
          SUM(COALESCE(NULLIF(pse, '')::DECIMAL, 1) * 10) as esforco_diario 
      FROM public.workouts_logs
      WHERE user_email = p_email AND done = 1
        AND workout_date >= p_end_date - INTERVAL '6 months'
      GROUP BY 1
  ),
  comparativo AS (
      SELECT 
          AVG(esforco_diario) as media_semestre,
          AVG(esforco_diario) FILTER (WHERE data_treino BETWEEN p_start_date AND p_end_date) as media_intervalo
      FROM daily_stats
  )
  SELECT 
      ROUND(media_intervalo, 1),
      ROUND(((media_intervalo - media_semestre) / NULLIF(media_semestre, 0)) * 100, 1)
  INTO v_esforco_atual, v_evolucao_percent
  FROM comparativo;

  -- 5. Weekly Frequency (no intervalo normalizado)
  SELECT ROUND(COUNT(DISTINCT workout_date)::DECIMAL / v_num_weeks, 1) INTO v_weekly_freq
  FROM public.workouts_logs
  WHERE user_email = p_email AND done = 1 
    AND workout_date BETWEEN p_start_date AND p_end_date;

  -- 6. Streak de Semanas (Meta: 3+ treinos/semana) - Mantido Global
  WITH weekly_counts AS (
      SELECT 
          DATE_TRUNC('week', workout_date)::DATE as week_start,
          COUNT(DISTINCT workout_date) as days_trained
      FROM public.workouts_logs
      WHERE user_email = p_email AND done = 1
      GROUP BY 1
  ),
  streak_calc AS (
      SELECT week_start, (CURRENT_DATE - week_start) / 7 as weeks_ago
      FROM weekly_counts
      WHERE days_trained >= 3
  ),
  consecutive_weeks AS (
      SELECT COUNT(*) as streak
      FROM (
          SELECT weeks_ago, ROW_NUMBER() OVER (ORDER BY weeks_ago) as rn
          FROM streak_calc
          WHERE weeks_ago <= 104
      ) s
      WHERE weeks_ago = rn - 1
  )
  SELECT COALESCE(streak, 0) INTO v_streak_weeks FROM consecutive_weeks;

  -- 7. Radar Data (no intervalo)
  SELECT jsonb_agg(radar_item) INTO v_radar_data
  FROM (
    SELECT LEFT(w.exercise_type, 15) as category, COUNT(wl.wod_exercise_id) as count
    FROM public.workouts w
    LEFT JOIN public.workouts_logs wl ON w.wod_exercise_id = wl.wod_exercise_id AND wl.done = 1
    WHERE w.user_email = p_email 
      AND w.exercise_type NOT LIKE 'http%' 
      AND length(w.exercise_type) > 1
      AND (w."date"::DATE BETWEEN p_start_date AND p_end_date OR wl.workout_date BETWEEN p_start_date AND p_end_date)
    GROUP BY 1 ORDER BY count DESC LIMIT 5
  ) radar_item;

  -- 8. Heatmap Data (no intervalo)
  SELECT jsonb_agg(heatmap_item) INTO v_heatmap_data
  FROM (
    SELECT workout_date::DATE as date, COUNT(*) FILTER (WHERE done = 1) as count, MAX(COALESCE(NULLIF(pse, '')::DECIMAL, 0)) as intensity
    FROM public.workouts_logs
    WHERE user_email = p_email AND workout_date BETWEEN p_start_date AND p_end_date
    GROUP BY 1 ORDER BY 1 ASC
  ) heatmap_item;

  -- Retorno JSON Final
  RETURN jsonb_build_object(
    'kpis', jsonb_build_object(
      'adherence', ROUND(COALESCE(v_adherence, 0), 1),
      'power_index', ROUND(COALESCE(v_power_index, 0), 0),
      'avg_pse', ROUND(COALESCE(v_avg_pse, 0), 1),
      'best_evolution', jsonb_build_object(
          'label', 'Esforço Global',
          'percent', COALESCE(v_evolucao_percent, 0)
      ),
      'current_workload', COALESCE(v_esforco_atual, 0),
      'weekly_freq', COALESCE(v_weekly_freq, 0),
      'streak', v_streak_weeks
    ),
    'radar', COALESCE(v_radar_data, '[]'::jsonb),
    'heatmap', COALESCE(v_heatmap_data, '[]'::jsonb)
  );
END;
$$;
