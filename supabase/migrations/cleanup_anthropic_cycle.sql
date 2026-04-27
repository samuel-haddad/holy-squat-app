-- ============================================================
-- PASSO 1: DIAGNÓSTICO — veja os coaches e treinos ativos
-- Execute este bloco primeiro para identificar o ai_coach_name
-- correto antes de apagar qualquer dado.
-- ============================================================

-- 1a. Lista todos os coaches com sessões geradas (AI ou manual)
SELECT
  ai_coach_name,
  COUNT(*)            AS total_sessions,
  MIN(date)           AS primeira_data,
  MAX(date)           AS ultima_data
FROM sessions
GROUP BY ai_coach_name
ORDER BY ultima_data DESC;

-- 1b. Veja os planos disponíveis e o coach associado
SELECT
  id,
  ai_coach_name,
  created_at::date    AS criado_em,
  start_date,
  end_date,
  array_length(mesos_ja_gerados, 1) AS mesos_gerados
FROM training_plans
ORDER BY created_at DESC
LIMIT 10;


-- ============================================================
-- PASSO 2: LIMPEZA — apaga os treinos do ciclo com problema
-- Substitua os valores entre <> pelos dados do PASSO 1.
-- ============================================================

-- Opção A: limpar pelo nome do coach (mais seguro se tiver 1 coach ativo)
-- Substitua 'NOME_DO_COACH_AQUI' pelo valor encontrado no PASSO 1.

/*
DO $$
DECLARE
  v_coach TEXT := 'NOME_DO_COACH_AQUI';   -- <-- substitua
  v_keys  TEXT[];
BEGIN
  -- Coleta as chaves das sessões do coach
  SELECT array_agg(date_session_sessiontype_key)
    INTO v_keys
    FROM sessions
   WHERE ai_coach_name = v_coach
     AND date >= CURRENT_DATE - INTERVAL '7 days';  -- janela de segurança

  IF v_keys IS NOT NULL THEN
    -- 1. Remove workouts linkados
    DELETE FROM workouts
     WHERE date_session_sessiontype_key = ANY(v_keys);
    RAISE NOTICE 'Workouts apagados: %', (SELECT count(*) FROM workouts WHERE date_session_sessiontype_key = ANY(v_keys));

    -- 2. Remove sessões
    DELETE FROM sessions
     WHERE date_session_sessiontype_key = ANY(v_keys);
    RAISE NOTICE 'Sessões apagadas para coach: %', v_coach;
  ELSE
    RAISE NOTICE 'Nenhuma sessão recente encontrada para coach: %', v_coach;
  END IF;
END $$;
*/


-- Opção B: limpar por plan_id (mais preciso — afeta só este ciclo)
-- Substitua 'SEU-PLAN-ID-AQUI' pelo UUID do plano encontrado no PASSO 1.

/*
DO $$
DECLARE
  v_plan_id UUID := 'SEU-PLAN-ID-AQUI';   -- <-- substitua
  v_keys    TEXT[];
BEGIN
  SELECT array_agg(date_session_sessiontype_key)
    INTO v_keys
    FROM sessions
   WHERE plan_id = v_plan_id;

  IF v_keys IS NOT NULL THEN
    DELETE FROM workouts
     WHERE date_session_sessiontype_key = ANY(v_keys);

    DELETE FROM sessions
     WHERE plan_id = v_plan_id;

    -- Limpa o meso que foi gerado (volta para o estado pré-geração)
    -- Só descomente se quiser reverter o mesos_ja_gerados também:
    -- UPDATE training_plans
    --    SET mesos_ja_gerados = array_remove(mesos_ja_gerados, mesos_ja_gerados[array_length(mesos_ja_gerados,1)])
    --  WHERE id = v_plan_id;

    RAISE NOTICE 'Limpeza do plan_id % concluída.', v_plan_id;
  ELSE
    RAISE NOTICE 'Nenhuma sessão encontrada para plan_id: %', v_plan_id;
  END IF;
END $$;
*/
