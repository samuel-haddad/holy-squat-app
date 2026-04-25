import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Valid session types for persistence validation
const validSessionTypes = new Set([
  'Acessório', 'Acessórios-Blindagem', 'Calistenia', 'Cardio', 'Cardio-Mobilidade',
  'Core', 'Core Strength', 'Core-Prep', 'Crossfit', 'Descanso', 'Endurance', 'EMOM', 'FBB',
  'Força-Heavy', 'Força-Metcon', 'Força-Skill', 'Full Body Pump', 'Full Session',
  'Ginástica-Metcon', 'Hipertrofia', 'Hipertrofia-Blindagem',
  'LPO', 'LPO-Força-Metcon', 'LPO-Metcon', 'LPO-Potência', 'Metcon',
  'Mobilidade', 'Mobilidade-Flow', 'Mobilidade-Cardio', 'Mobilidade-Core',
  'Mobilidade-Inferiores', 'Mobilidade-Prep', 'Multi', 'Musculação',
  'Musculação-Cardio', 'Musculação-Funcional', 'Musculação-Força',
  'Natação', 'Prehab', 'Prehab-Força', 'Prehab-Mobilidade', 'Recuperação Ativa',
  'Reintrodução-FBB', 'Skill', 'Skill-Metcon',
]);

// =========================================================
// Main handler
// =========================================================
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  try {
    const { job_id } = await req.json();
    if (!job_id) {
      return new Response(JSON.stringify({ error: 'job_id required' }), { headers: corsHeaders, status: 400 });
    }
    // Aguardamos o processamento do step atual terminar antes de liberar o container
    await processJob(job_id);
    
    return new Response(JSON.stringify({ received: true, job_id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500,
    });
  }
});

// =========================================================
// Background processor
// =========================================================
async function processJob(jobId: string) {
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  const { data: job, error } = await admin
    .from('ai_generation_jobs').select('*').eq('id', jobId).single();

  if (error || !job) { console.error(`[orch] Job ${jobId} not found:`, error); return; }
  if (job.status === 'completed' || job.status === 'error' || job.status === 'pending_approval') { return; }

  await admin.from('ai_generation_jobs')
    .update({ status: 'processing', updated_at: new Date().toISOString() })
    .eq('id', jobId);

  try {
    if (job.job_type === 'create_plan') {
      await handleCreatePlanStep(job, admin);
    } else if (job.job_type === 'generate_cycle') {
      await handleGenerateCycleStep(job, admin);
    } else if (job.job_type === 'generate_workouts') {
      await handleGenerateWorkoutsStep(job, admin);
    } else {
      throw new Error(`Unknown job_type: ${job.job_type}`);
    }
  } catch (err: any) {
    console.error(`[orch] Job ${jobId} step ${job.current_step} failed:`, err);
    await admin.from('ai_generation_jobs')
      .update({ status: 'error', error_message: err.message || 'Unknown', updated_at: new Date().toISOString() })
      .eq('id', jobId);
  }
}

// =========================================================
// HTTP call to gerar-treino with 55s timeout
// =========================================================
async function callGerarTreino(payload: any, functionName: string): Promise<any> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() || Deno.env.get('SUPABASE_ANON_KEY')?.trim() || '';
  
  const url = `${supabaseUrl}/functions/v1/${functionName}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 300000);

  try {
    console.log(`[orch] calling ${functionName}:${payload.acao}...`);
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
        'apikey': serviceKey,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!resp.ok) {
      const errText = await resp.text();
      throw new Error(`${functionName} [${payload.acao}] (${resp.status}): ${errText.substring(0, 500)}`);
    }
    return await resp.json();
  } catch (err: any) {
    if (err.name === 'AbortError') {
      throw new Error(`Timeout: a função ${functionName} (${payload.acao}) excedeu 300s.`);
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }
}

// =========================================================
// CREATE_PLAN: Step 1 (Ação 1) → Step 2 (Ação 2) → Persist
// "3, 2, 1... GO!" button
// =========================================================
async function handleCreatePlanStep(job: any, admin: any) {
  const step = job.current_step;
  const p = job.input_params;

  if (step === 1) {
    console.log(`[orch] create_plan step 1: gerar_analise_historica`);
    const result = await callGerarTreino({
      acao: 'gerar_analise_historica',
      user_id: job.user_id,
      email_utilizador: p.email_utilizador,
      ai_coach_name: p.ai_coach_name,
      training_sessions: p.training_sessions || [],
    }, 'gerar-plano');
    await admin.from('ai_generation_jobs').update({
      step_1_result: result, current_step: 2, updated_at: new Date().toISOString(),
    }).eq('id', job.id);

  } else if (step === 2) {
    console.log(`[orch] create_plan step 2: criar_plano`);
    const result = await callGerarTreino({
      acao: 'criar_plano',
      user_id: job.user_id,
      email_utilizador: p.email_utilizador,
      analise_historica: job.step_1_result,
      diretrizes_plano: p.diretrizes_plano,
      training_sessions: p.training_sessions || [],
      ai_coach_name: p.ai_coach_name,
    }, 'gerar-plano');

    // PERSIST: create training_plan with analysis + plan blocks
    const planId = await persistCreatePlan(job, result, admin);

    await admin.from('ai_generation_jobs').update({
      step_2_result: result, plan_id: planId,
      status: 'completed', updated_at: new Date().toISOString(),
    }).eq('id', job.id);

    console.log(`[orch] create_plan COMPLETED. plan_id=${planId}`);
  }
}

// =========================================================
// GENERATE_CYCLE: Step 1 (Ação 3) → Step 2 (Ação 4) → Persist
// "Next Cycle" button
// =========================================================
async function handleGenerateCycleStep(job: any, admin: any) {
  const step = job.current_step;
  const p = job.input_params;

  if (step === 1) {
    console.log(`[orch] generate_cycle step 1: gerar_analise`);

    // Read training_plan for macro context (memory)
    let contextoMacrociclo: any = {};
    if (p.plano_id) {
      const { data: plan } = await admin
        .from('training_plans').select('workouts_plan_text, actual_plan_summary, competitions').eq('id', p.plano_id).single();
      if (plan) {
        let analise = {};
        let visao = {};
        try { analise = JSON.parse(plan.workouts_plan_text || '{}'); } catch (_) { }
        try { visao = JSON.parse(plan.actual_plan_summary || '{}'); } catch (_) { }
        contextoMacrociclo = {
          analise_historica: analise,
          visao_geral_plano: visao,
          competicoes: plan.competitions || []
        };
      }
    }

    // Identify next block
    let planSummary: any = {};
    try { planSummary = JSON.parse(p.actual_plan_summary_json || '{}'); } catch (_) { }
    const blocos = planSummary.blocos || [];
    const mesosJaGerados: string[] = p.mesos_ja_gerados || [];
    const proximoMeso = blocos.find((b: any) => !mesosJaGerados.includes(b.mesociclo)) || {};

    // Fetch performance stats (Last Meso Interval)
    let performanceStats = null;
    let cycleSnapshot = null;
    const ultimoMeso = mesosJaGerados.length > 0 ? mesosJaGerados[mesosJaGerados.length - 1] : null;

    // Determine start date of the mesocycle that just finished
    const mesoStartDate = p.current_workouts_table?.[0]?.date || new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
    const today = new Date().toISOString().split('T')[0];

    if (p.plano_id) {
      // 1. Fetch detailed performance stats for LLM analysis
      if (ultimoMeso) {
        const { data } = await admin.rpc('get_mesocycle_performance_stats', {
          p_plan_id: p.plano_id, p_mesocycle_name: ultimoMeso,
        });
        performanceStats = data;
      }

      // 2. Fetch general KPIs snapshot for the specific meso interval
      const { data: statsRange } = await admin.rpc('get_athlete_stats_by_range', {
        p_email: p.email_utilizador, p_start_date: mesoStartDate, p_end_date: today
      });
      cycleSnapshot = statsRange;
    }

    // Fetch user profile and training sessions for context
    const { data: profile } = await admin.from('profiles').select('id').eq('email', p.email_utilizador).single();
    let trainingSessions = p.training_sessions || [];

    if (profile?.id && trainingSessions.length === 0) {
      const { data: sessionsData } = await admin
        .from('training_sessions')
        .select('session_number, locations, duration_minutes, schedule, time_of_day, notes')
        .eq('user_id', profile.id)
        .order('session_number', { ascending: true });
      if (sessionsData) trainingSessions = sessionsData;
    }

    const result = await callGerarTreino({
      acao: 'gerar_analise',
      user_id: job.user_id,
      email_utilizador: p.email_utilizador,
      bloco_atual: proximoMeso,
      performance_stats: performanceStats,
      cycle_snapshot: cycleSnapshot,
      contexto_macrociclo: contextoMacrociclo,
      training_sessions: trainingSessions,
      ai_coach_name: p.ai_coach_name,
    }, 'gerar-analise-ciclo');

    await admin.from('ai_generation_jobs').update({
      step_1_result: {
        ...result,
        _blocoAtual: proximoMeso,
        _cycleSnapshot: cycleSnapshot,
        _performanceStats: performanceStats,
        _trainingSessions: trainingSessions,
      },
      current_step: 2,
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

  } else if (step === 2) {
    console.log(`[orch] generate_cycle step 2: gerar_calendario`);
    const p = job.input_params;
    const cicloResult = job.step_1_result || {};
    
    const result = await callGerarTreino({
      acao: 'gerar_calendario',
      user_id: job.user_id,
      email_utilizador: p.email_utilizador,
      bloco_atual: cicloResult._blocoAtual,
      visao_geral: cicloResult.visaoGeralCiclo,
      data_inicio_meso: cicloResult._blocoAtual?.dataInicioMeso || p.data_inicio_macro,
      training_sessions: cicloResult._trainingSessions || p.training_sessions || [],
      ai_coach_name: p.ai_coach_name,
    }, 'gerar-analise-ciclo');

    job.step_1_result = {
      ...cicloResult,
      visaoSemanal: result.visaoSemanal
    };

    // Persiste os resultados intermediários (Análise + Calendário)
    await persistGenerateCycle(job, [], admin);

    await admin.from('ai_generation_jobs').update({
      step_1_result: job.step_1_result,
      current_step: 3,
      status: 'completed', // Finaliza aqui. O detalhamento (exercícios) será outro Job.
      updated_at: new Date().toISOString(),
    }).eq('id', job.id).throwOnError();

  } else if (step >= 3) {
    // Fallback de segurança se o step passar dos dias configurados no job antigo
    await admin.from('ai_generation_jobs').update({
      status: 'completed', updated_at: new Date().toISOString(),
    }).eq('id', job.id);
  }
}

// =========================================================
// GENERATE_WORKOUTS: Ação 4 (Loop diário)
// "Workouts" button
// =========================================================
async function handleGenerateWorkoutsStep(job: any, admin: any) {
  const step = job.current_step;
  const p = job.input_params;
  const visaoSemanal = p.visao_semanal || [];
  const blocoAtual = p.bloco_atual || {};
  const trainingSessions = p.training_sessions || [];
  const planSummary = p.plan_summary || {};

  const activeDays = visaoSemanal.filter((d: any) => !d.isDescansoAtivo);
  const dayIndex = step - 1; // Inicia no step 1

  if (dayIndex < activeDays.length) {
    const dia = activeDays[dayIndex];
    const weekNum = dia.week || 1;
    console.log(`[orch] Processando exercícios dia ${dia.date} (Step: ${step} / Total: ${activeDays.length})`);

    const accumulatedExercicios = job.step_1_result?.exerciciosDetalhados || [];
    const exerciciosDaSemana = accumulatedExercicios.filter((ex: any) => ex.week === weekNum);

    const result = await callGerarTreino({
      acao: 'gerar_detalhamento',
      user_id: job.user_id,
      email_utilizador: p.email_utilizador,
      visao_diaria: [dia],
      exercicios_da_semana: exerciciosDaSemana,
      meso_context: {
        nome: blocoAtual.mesociclo || 'Próximo Meso',
        objetivo: planSummary.objetivoPrincipal || '',
        semanaNum: weekNum,
        totalSemanas: 4,
        focoSemana: blocoAtual.foco || '',
        trainingSessions: trainingSessions,
      },
      ai_coach_name: p.ai_coach_name,
    }, 'gerar-exercicios');

    const newExercicios = result.exerciciosDetalhados || [];
    const allExercicios = [...accumulatedExercicios, ...newExercicios];

    if (dayIndex === activeDays.length - 1) {
      // Último dia: persiste e finaliza
      await persistExercicios(allExercicios, p.email_utilizador, p.plano_id, p.ai_coach_name, admin);

      await admin.from('ai_generation_jobs').update({
        step_1_result: { exerciciosDetalhados: allExercicios },
        status: 'completed', updated_at: new Date().toISOString(),
      }).eq('id', job.id);

      console.log(`[orch] generate_workouts COMPLETED. total exercises=${allExercicios.length}`);
    } else {
      // Próximo dia
      await admin.from('ai_generation_jobs').update({
        step_1_result: { exerciciosDetalhados: allExercicios },
        current_step: step + 1, updated_at: new Date().toISOString(),
      }).eq('id', job.id);
    }
  } else {
    await admin.from('ai_generation_jobs').update({
      status: 'completed', updated_at: new Date().toISOString(),
    }).eq('id', job.id);
  }
}

// =========================================================
// Persistence: create_plan → save training_plan record
// =========================================================
async function persistCreatePlan(job: any, planResult: any, admin: any): Promise<string> {
  const p = job.input_params;
  const userId = job.user_id;

  if (!userId) throw new Error(`User ID missing in job ${job.id}`);

  const today = new Date().toISOString().split('T')[0];

  // Clean old future AI sessions for this coach
  await admin.from('sessions').delete()
    .eq('user_email', p.email_utilizador)
    .eq('ai_coach_name', p.ai_coach_name || 'Human Coach')
    .not('plan_id', 'is', null)
    .gt('date', today);

  const { data: planRecord, error } = await admin.from('training_plans').insert({
    user_id: userId,
    start_date: p.diretrizes_plano?.data_inicio,
    end_date: p.diretrizes_plano?.data_fim || null,
    notes: p.diretrizes_plano?.notas || null,
    competitions: (p.diretrizes_plano?.competicoes || []).map((c: any) => ({
      name: c.name,
      start_date: c.start_date,
      end_date: c.end_date
    })),
    actual_plan_summary: JSON.stringify(planResult?.visaoGeralPlano || {}),
    workouts_plan_text: JSON.stringify(job.step_1_result?.analiseMacro || {}),
    workouts_plan_table: [],
    snapshot_stats: job.step_1_result?.athlete_stats_snapshot || null,
    ai_coach_name: p.ai_coach_name || 'Human Coach',
  }).select('id').single();

  if (error) throw new Error(`Failed to save training plan: ${error.message}`);
  return planRecord?.id;
}

// =========================================================
// Persistence: generate_cycle → save sessions + workouts
// =========================================================
async function persistGenerateCycle(job: any, exercicios: any[], admin: any) {
  const p = job.input_params;
  const cicloResult = job.step_1_result || {};

  let planSummary: any = {};
  try { planSummary = JSON.parse(p.actual_plan_summary_json || '{}'); } catch (_) { }

  // Recover performanceStats that was stashed in step_1_result during step 1.
  // Its kpis (completion_rate, weekly_freq, load_delta, pr_recovery, neglected_type)
  // and charts (planned_vs_realized, load_vs_pse, volume_by_group) are needed by Flutter
  // to render _buildProgressKpisGrid and the three progress charts.
  const performanceStats = cicloResult._performanceStats || null;

  // Validate cycleSnapshot has real data before saving (same guard as create_plan flow)
  const rawSnapshot = cicloResult._cycleSnapshot;
  const hasValidSnapshot = rawSnapshot && rawSnapshot.kpis && rawSnapshot.radar !== undefined;

  const currentMesoName = cicloResult._blocoAtual?.mesociclo;
  const mesosJaGerados = Array.isArray(p.mesos_ja_gerados) ? [...p.mesos_ja_gerados] : [];
  if (currentMesoName && !mesosJaGerados.includes(currentMesoName)) {
    mesosJaGerados.push(currentMesoName);
  }

  await admin.from('training_plans').update({
    progress_analysis: JSON.stringify({
      // Narrative text fields from the LLM (texto, resumo, etc)
      ...(cicloResult.analiseCicloAnterior || {}),
      mesocycle_summary: cicloResult.resumoMesociclo || null,
      // Structured KPIs from get_mesocycle_performance_stats → renders progress grid + charts
      kpis: performanceStats?.kpis || null,
      charts: performanceStats?.charts || null,
      // Athlete snapshot from get_athlete_stats_by_range → renders cycle_snapshot section
      cycle_snapshot: hasValidSnapshot ? rawSnapshot : null,
    }),
    workouts_plan_table: [
      ...(p.current_workouts_table || []),
      ...(cicloResult.visaoSemanal || []),
    ],
    mesos_ja_gerados: mesosJaGerados,
  }).eq('id', p.plano_id).throwOnError();

  // Save exercises
  await persistExercicios(exercicios, p.email_utilizador, p.plano_id, p.ai_coach_name, admin);
}

// =========================================================
// Shared: persist sessions + workouts
// =========================================================
async function persistExercicios(
  exercicios: any[], email: string, planId: string | null, aiCoachName: string | null, admin: any
) {
  if (!exercicios.length) return;

  const uniqueSessions: Record<string, any> = {};
  const records: any[] = [];

  for (let i = 0; i < exercicios.length; i++) {
    const ex = exercicios[i];
    let st = (ex.session_type || 'Crossfit').trim();
    if (!validSessionTypes.has(st)) {
      console.warn(`[persist] Invalid session_type: "${st}" → Crossfit`);
      st = 'Crossfit';
    }

    const sessionKey = `${ex.date}_${ex.session}_${st}`;
    if (!uniqueSessions[sessionKey]) {
      uniqueSessions[sessionKey] = {
        date_session_sessiontype_key: sessionKey,
        date: ex.date, session: ex.session, session_type: st,
        duration: ex.duration,
        user_email: email,
        ...(planId ? { plan_id: planId } : {}),
        ...(aiCoachName ? { ai_coach_name: aiCoachName } : {}),
      };
    }

    records.push({
      date: ex.date, week: ex.week, mesocycle: ex.mesocycle, day: ex.day,
      session: ex.session, session_type: st,
      workout_idx: ex.workout_idx, exercise: ex.exercise,
      exercise_title: ex.exercise_title, exercise_group: ex.exercise_group,
      exercise_type: ex.exercise_type, sets: ex.sets, details: ex.details,
      time_exercise: ex.time_exercise, ex_unit: ex.ex_unit,
      rest: ex.rest, rest_unit: ex.rest_unit,
      total_time: ex.total_time, location: ex.location, stage: ex.stage,
      workout_link: ex.workout_link || '', adaptacaoLesao: ex.adaptacaoLesao || '',
      user_email: email, date_session_sessiontype_key: sessionKey,
      wod_exercise_id: `${ex.date}_${ex.session}_${ex.workout_idx}_${Date.now() % 100000}_${i}`,
    });
  }

  const sessions = Object.values(uniqueSessions);
  const sessionKeys = sessions.map(s => s.date_session_sessiontype_key);

  if (sessions.length > 0) {
    const { error } = await admin.from('sessions').upsert(sessions, { onConflict: 'date_session_sessiontype_key' });
    if (error) console.error('[persist] sessions upsert error:', error);
  }

  if (records.length > 0) {
    // CLEANUP: Remove old workouts for these specific sessions before inserting new ones
    const { error: delError } = await admin.from('workouts')
      .delete()
      .in('date_session_sessiontype_key', sessionKeys);
    if (delError) console.error('[persist] workouts cleanup error:', delError);

    const { error } = await admin.from('workouts').insert(records);
    if (error) console.error('[persist] workouts insert error:', error);
  }
  console.log(`[persist] Saved ${sessions.length} sessions + ${records.length} workouts`);
}
