-- Simplificação da tabela sessions
ALTER TABLE sessions DROP COLUMN IF EXISTS week;
ALTER TABLE sessions DROP COLUMN IF EXISTS day;

-- Simplificação da tabela workouts
ALTER TABLE workouts DROP COLUMN IF EXISTS week;
ALTER TABLE workouts DROP COLUMN IF EXISTS exercise_title;
ALTER TABLE workouts DROP COLUMN IF EXISTS exercise_group;
ALTER TABLE workouts DROP COLUMN IF EXISTS exercise_type;
ALTER TABLE workouts DROP COLUMN IF EXISTS location;

-- Atualização do RPC get_athlete_planning_stats para não quebrar sem exercise_type
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
            w.exercise,
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
              w.exercise ILIKE '%overhead press%'
            )
          GROUP BY w.exercise
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
        SELECT LEFT(w.exercise, 15) AS category, COUNT(*) AS count
        FROM public.workouts w
        WHERE w.user_email = p_email 
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

-- Atualização do RPC get_athlete_stats_by_range
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
            w.exercise,
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
              w.exercise ILIKE '%overhead press%'
            )
          GROUP BY w.exercise
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
        SELECT LEFT(w.exercise, 15) AS category, COUNT(*) AS count
        FROM public.workouts w
        WHERE w.user_email = p_email
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

-- Atualização do RPC get_athlete_history_summary
CREATE OR REPLACE FUNCTION public.get_athlete_history_summary(p_email TEXT)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
AS $$
WITH
  -- ── Base: workouts dos últimos 12 meses ──────────────────────────────
  bw AS (
    SELECT
      w.date::date                         AS day,
      TO_CHAR(w.date::date, 'YYYY-MM')     AS month,
      w.session,
      w.exercise                           AS exercise_title, -- Usando exercise como título
      w.stage
    FROM workouts AS w
    WHERE w.user_email = p_email
      AND w.date::date >= (CURRENT_DATE - INTERVAL '12 months')::date
  ),

  -- ── Cargas diárias (join com workouts_logs) ──────────────────────────
  dl AS (
    SELECT
      l.workout_date                                                                        AS day,
      MIN(l.weight::numeric)    FILTER (WHERE l.weight::numeric        > 0)                AS min_w,
      ROUND(AVG(l.weight::numeric)    FILTER (WHERE l.weight::numeric  > 0), 1)            AS avg_w,
      MAX(l.weight::numeric)    FILTER (WHERE l.weight::numeric        > 0)                AS max_w,
      ROUND(AVG(l.reps_done::numeric)     FILTER (WHERE l.reps_done::numeric    > 0), 1)   AS avg_reps,
      ROUND(AVG(l.cardio_result::numeric) FILTER (WHERE l.cardio_result::numeric > 0), 1)  AS avg_cardio,
      MAX(l.cardio_unit)                                                                    AS cardio_unit
    FROM workouts_logs AS l
    WHERE l.user_email = p_email
      AND l.workout_date >= (CURRENT_DATE - INTERVAL '12 months')::date
      AND (l.weight IS NULL OR l.weight::text ~ '^[0-9]+(\.[0-9]+)?$')
      AND (l.reps_done IS NULL OR l.reps_done::text ~ '^[0-9]+(\.[0-9]+)?$')
      AND (l.cardio_result IS NULL OR l.cardio_result::text ~ '^[0-9]+(\.[0-9]+)?$')
    GROUP BY l.workout_date
  ),

  mv AS (
    SELECT
      bw.month,
      COUNT(DISTINCT bw.day)                                                          AS training_days,
      COUNT(DISTINCT bw.day::text || '_' || COALESCE(bw.session::text, '1'))         AS sessions
    FROM bw
    GROUP BY bw.month
  ),
  
  -- Removendo distribuição por grupo já que exercise_group foi deletado
  monthly_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'month',      mv.month,
        'train_days', mv.training_days,
        'sessions',   mv.sessions,
        'group_pct',  '{}'::jsonb
      ) ORDER BY mv.month
    ) AS data
    FROM mv
  ),

  sa AS (
    SELECT
      bw.exercise_title,
      COUNT(DISTINCT bw.day)                                                               AS freq,
      MAX(bw.day)                                                                          AS last_date,
      MIN(dl.min_w)                                                                        AS load_min,
      ROUND(AVG(dl.avg_w), 1)                                                              AS load_avg,
      MAX(dl.max_w)                                                                        AS load_max,
      AVG(dl.avg_w) FILTER (
        WHERE bw.day BETWEEN (CURRENT_DATE - INTERVAL '12 months')::date
                         AND (CURRENT_DATE - INTERVAL '9 months')::date
      )                                                                                    AS q1_avg,
      AVG(dl.avg_w) FILTER (
        WHERE bw.day >= (CURRENT_DATE - INTERVAL '3 months')::date
      )                                                                                    AS q4_avg
    FROM bw
    JOIN dl ON dl.day = bw.day
    WHERE bw.stage IN ('strength', 'skill')
      AND dl.max_w > 0
    GROUP BY bw.exercise_title
    HAVING COUNT(DISTINCT bw.day) >= 2
  ),
  strength_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'exercise',  exercise_title,
        'group',     'Geral',
        'freq',      freq,
        'load_min',  load_min,
        'load_avg',  load_avg,
        'load_max',  load_max,
        'last',      last_date,
        'trend',     CASE
                       WHEN q4_avg IS NOT NULL AND q1_avg IS NOT NULL
                            AND q4_avg > q1_avg * 1.05 THEN 'crescente'
                       WHEN q4_avg IS NOT NULL AND q1_avg IS NOT NULL
                            AND q4_avg < q1_avg * 0.95 THEN 'regressiva'
                       ELSE 'estável'
                     END
      ) ORDER BY load_max DESC NULLS LAST
    ) AS data
    FROM sa
  ),

  ma AS (
    SELECT
      bw.exercise_title,
      COUNT(DISTINCT bw.day)                                          AS freq,
      BOOL_OR(dl.avg_w IS NOT NULL AND dl.avg_w > 0)                 AS has_weight,
      MIN(dl.min_w)                                                   AS load_min,
      ROUND(AVG(dl.avg_w) FILTER (WHERE dl.avg_w > 0), 1)            AS load_avg,
      MAX(dl.max_w)                                                   AS load_max,
      ROUND(AVG(dl.avg_reps),    1)                                   AS avg_reps,
      ROUND(AVG(dl.avg_cardio),  1)                                   AS avg_cardio,
      MAX(dl.cardio_unit)                                             AS cardio_unit
    FROM bw
    LEFT JOIN dl ON dl.day = bw.day
    WHERE bw.stage = 'workout'
    GROUP BY bw.exercise_title
  ),
  metcon_top AS (
    SELECT * FROM ma ORDER BY freq DESC LIMIT 20
  ),
  metcon_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'exercise',    exercise_title,
        'group',       'Geral',
        'freq',        freq,
        'has_weight',  has_weight,
        'load_min',    load_min,
        'load_avg',    load_avg,
        'load_max',    load_max,
        'avg_reps',    avg_reps,
        'avg_cardio',  avg_cardio,
        'cardio_unit', cardio_unit
      ) ORDER BY freq DESC
    ) AS data
    FROM metcon_top
  ),

  top15_raw AS (
    SELECT
      bw.exercise_title,
      COUNT(DISTINCT bw.day)  AS freq,
      MAX(bw.day)             AS last_date
    FROM bw
    WHERE bw.stage NOT IN ('warmup', 'cooldown')
    GROUP BY bw.exercise_title
    ORDER BY freq DESC
    LIMIT 15
  ),
  top15_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'exercise', exercise_title,
        'group',    'Geral',
        'type',     'Acessório',
        'freq',     freq,
        'last',     last_date
      )
    ) AS data
    FROM top15_raw
  ),

  qb AS (
    SELECT
      bw.exercise_title,
      CONCAT(
        EXTRACT(year    FROM bw.day)::int, '-Q',
        EXTRACT(quarter FROM bw.day)::int
      )                               AS q,
      ROUND(AVG(dl.avg_w), 1)         AS avg_load,
      MAX(dl.max_w)                   AS max_load
    FROM bw
    JOIN dl ON dl.day = bw.day
    WHERE bw.exercise_title IN (
      'Back Squat', 'Deadlift', 'Press', 'Push Press',
      'Clean & Jerk', 'Snatch', 'Front Squat', 'Bench Press'
    )
      AND dl.avg_w > 0
    GROUP BY bw.exercise_title, q
  ),
  qp AS (
    SELECT
      qb.exercise_title,
      jsonb_agg(
        jsonb_build_object('q', qb.q, 'avg', qb.avg_load, 'max', qb.max_load)
        ORDER BY qb.q
      ) AS quarters
    FROM qb
    GROUP BY qb.exercise_title
  ),
  progress_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object('exercise', exercise_title, 'quarters', quarters)
    ) AS data
    FROM qp
  )

SELECT jsonb_build_object(
  'monthly_profile',       (SELECT data FROM monthly_agg),
  'strength_describe',     (SELECT data FROM strength_agg),
  'metcon_describe',       (SELECT data FROM metcon_agg),
  'top_exercises',         (SELECT data FROM top15_agg),
  'quarterly_progression', (SELECT data FROM progress_agg)
);
$$;

