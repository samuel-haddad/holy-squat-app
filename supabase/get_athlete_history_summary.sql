-- =============================================================
-- RPC: get_athlete_history_summary
-- LANGUAGE sql (não plpgsql) — evita o bug do Supabase SQL Editor
-- que interpreta SELECT INTO como criação de tabela.
-- O corpo inteiro é uma única query SQL com CTEs em cascata.
-- =============================================================
CREATE OR REPLACE FUNCTION get_athlete_history_summary(p_email TEXT)
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
      w.exercise_title,
      w.exercise_group,
      w.exercise_type,
      w.stage
    FROM workouts AS w
    WHERE w.user_email = p_email
      AND w.date::date >= (CURRENT_DATE - INTERVAL '12 months')::date
  ),

  -- ── Cargas diárias (join com workouts_logs) ──────────────────────────
  -- Limitação: join por data (não por exercício), cargas são aproximadas
  -- Nota: weight, reps_done e cardio_result são TEXT no banco → cast ::numeric
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
      -- Only process rows where numeric columns actually contain numbers to avoid crash on "6+10" style strings
      AND (l.weight IS NULL OR l.weight::text ~ '^[0-9]+(\.[0-9]+)?$')
      AND (l.reps_done IS NULL OR l.reps_done::text ~ '^[0-9]+(\.[0-9]+)?$')
      AND (l.cardio_result IS NULL OR l.cardio_result::text ~ '^[0-9]+(\.[0-9]+)?$')
    GROUP BY l.workout_date
  ),

  -- ════════════════════════════════════════════════════════════════════
  -- MÓDULO 1 — Perfil mensal: volume + distribuição de grupos
  -- ════════════════════════════════════════════════════════════════════
  mv AS (
    SELECT
      bw.month,
      COUNT(DISTINCT bw.day)                                                          AS training_days,
      COUNT(DISTINCT bw.day::text || '_' || COALESCE(bw.session::text, '1'))         AS sessions
    FROM bw
    GROUP BY bw.month
  ),
  gr AS (
    SELECT
      bw.month,
      COALESCE(bw.exercise_group, 'Outro')  AS grp,
      COUNT(*)                              AS cnt
    FROM bw
    WHERE bw.stage NOT IN ('warmup', 'cooldown')
    GROUP BY bw.month, COALESCE(bw.exercise_group, 'Outro')
  ),
  gt AS (
    SELECT gr.month, SUM(gr.cnt) AS total FROM gr GROUP BY gr.month
  ),
  gp AS (
    SELECT
      gr.month,
      jsonb_object_agg(gr.grp, ROUND(gr.cnt * 100.0 / NULLIF(gt.total, 0), 0)) AS pct
    FROM gr JOIN gt ON gr.month = gt.month
    GROUP BY gr.month
  ),
  monthly_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'month',      mv.month,
        'train_days', mv.training_days,
        'sessions',   mv.sessions,
        'group_pct',  gp.pct
      ) ORDER BY mv.month
    ) AS data
    FROM mv LEFT JOIN gp ON mv.month = gp.month
  ),

  -- ════════════════════════════════════════════════════════════════════
  -- MÓDULO 2 — Exercícios de Força: describe (min/avg/max + tendência)
  -- ════════════════════════════════════════════════════════════════════
  sa AS (
    SELECT
      bw.exercise_title,
      bw.exercise_group,
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
    GROUP BY bw.exercise_title, bw.exercise_group
    HAVING COUNT(DISTINCT bw.day) >= 2
  ),
  strength_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'exercise',  exercise_title,
        'group',     exercise_group,
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

  -- ════════════════════════════════════════════════════════════════════
  -- MÓDULO 3 — WODs / Metcons
  --   - com carga       → min/avg/max kg
  --   - cardio puro     → avg resultado (m, cal, km…)
  --   - sem log         → frequência + reps médias
  -- ════════════════════════════════════════════════════════════════════
  ma AS (
    SELECT
      bw.exercise_title,
      bw.exercise_group,
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
    GROUP BY bw.exercise_title, bw.exercise_group
  ),
  metcon_top AS (
    SELECT * FROM ma ORDER BY freq DESC LIMIT 20
  ),
  metcon_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'exercise',    exercise_title,
        'group',       exercise_group,
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

  -- ════════════════════════════════════════════════════════════════════
  -- MÓDULO 4 — Top 15 exercícios por frequência
  -- ════════════════════════════════════════════════════════════════════
  top15_raw AS (
    SELECT
      bw.exercise_title,
      bw.exercise_group,
      bw.exercise_type,
      COUNT(DISTINCT bw.day)  AS freq,
      MAX(bw.day)             AS last_date
    FROM bw
    WHERE bw.stage NOT IN ('warmup', 'cooldown')
    GROUP BY bw.exercise_title, bw.exercise_group, bw.exercise_type
    ORDER BY freq DESC
    LIMIT 15
  ),
  top15_agg AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'exercise', exercise_title,
        'group',    exercise_group,
        'type',     exercise_type,
        'freq',     freq,
        'last',     last_date
      )
    ) AS data
    FROM top15_raw
  ),

  -- ════════════════════════════════════════════════════════════════════
  -- MÓDULO 5 — Progressão trimestral dos levantamentos-chave
  -- ════════════════════════════════════════════════════════════════════
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

-- ── Resultado final ──────────────────────────────────────────────────
SELECT jsonb_build_object(
  'monthly_profile',       (SELECT data FROM monthly_agg),
  'strength_describe',     (SELECT data FROM strength_agg),
  'metcon_describe',       (SELECT data FROM metcon_agg),
  'top_exercises',         (SELECT data FROM top15_agg),
  'quarterly_progression', (SELECT data FROM progress_agg)
);
$$;

-- Garante acesso pela anon key, authenticated e service_role
GRANT EXECUTE ON FUNCTION get_athlete_history_summary(TEXT) TO anon, authenticated, service_role;
