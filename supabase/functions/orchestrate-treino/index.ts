import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Valid session types for persistence validation (must match DB/icons table)
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
// Main handler: receives webhook, processes in background
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

    // Process in background so pg_net gets a quick response
    // @ts-ignore: EdgeRuntime is a Supabase global
    EdgeRuntime.waitUntil(processJob(job_id));

    return new Response(JSON.stringify({ received: true, job_id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});

// =========================================================
// Background processor
// =========================================================
async function processJob(jobId: string) {
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  const { data: job, error } = await supabaseAdmin
    .from('ai_generation_jobs')
    .select('*')
    .eq('id', jobId)
    .single();

  if (error || !job) {
    console.error(`[orchestrate] Job ${jobId} not found:`, error);
    return;
  }

  if (job.status === 'completed' || job.status === 'error') {
    console.log(`[orchestrate] Job ${jobId} already ${job.status}. Skipping.`);
    return;
  }

  // Mark as processing
  await supabaseAdmin.from('ai_generation_jobs')
    .update({ status: 'processing', updated_at: new Date().toISOString() })
    .eq('id', jobId);

  try {
    if (job.job_type === 'new_plan') {
      await handleNewPlanStep(job, supabaseAdmin);
    } else if (job.job_type === 'next_cycle') {
      await handleNextCycleStep(job, supabaseAdmin);
    } else {
      throw new Error(`Unknown job_type: ${job.job_type}`);
    }
  } catch (err: any) {
    console.error(`[orchestrate] Job ${jobId} step ${job.current_step} failed:`, err);
    await supabaseAdmin.from('ai_generation_jobs')
      .update({
        status: 'error',
        error_message: err.message || 'Unknown error',
        updated_at: new Date().toISOString(),
      })
      .eq('id', jobId);
  }
}

// =========================================================
// Internal HTTP call to gerar-treino Edge Function
// =========================================================
async function callGerarTreino(payload: any): Promise<any> {
  const url = `${Deno.env.get('SUPABASE_URL')}/functions/v1/gerar-treino`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`gerar-treino [${payload.acao}] failed (${response.status}): ${errText.substring(0, 500)}`);
  }

  return response.json();
}

// =========================================================
// NEW PLAN: Steps 1 → 2 → 3 → 4
// =========================================================
async function handleNewPlanStep(job: any, admin: any) {
  const step = job.current_step;
  const params = job.input_params;

  if (step === 1) {
    console.log(`[orchestrate] new_plan step 1: gerar_analise_historica`);
    const result = await callGerarTreino({
      acao: 'gerar_analise_historica',
      email_utilizador: params.email_utilizador,
      ai_coach_name: params.ai_coach_name,
    });
    await admin.from('ai_generation_jobs').update({
      step_1_result: result,
      current_step: 2,
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

  } else if (step === 2) {
    console.log(`[orchestrate] new_plan step 2: criar_plano`);
    const result = await callGerarTreino({
      acao: 'criar_plano',
      email_utilizador: params.email_utilizador,
      analise_historica: job.step_1_result,
      diretrizes_plano: params.diretrizes_plano,
      perfil_atleta: params.perfil_atleta,
      ai_coach_name: params.ai_coach_name,
    });
    await admin.from('ai_generation_jobs').update({
      step_2_result: result,
      current_step: 3,
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

  } else if (step === 3) {
    console.log(`[orchestrate] new_plan step 3: gerar_proximo_ciclo (Meso 1)`);
    const blocos = job.step_2_result?.visaoGeralPlano?.blocos || [];
    const meso1 = blocos[0] || {};

    const result = await callGerarTreino({
      acao: 'gerar_proximo_ciclo',
      email_utilizador: params.email_utilizador,
      bloco_atual: meso1,
      performance_stats: null,
      dias_treino: {
        sessions_per_day: params.perfil_atleta?.sessions_per_day || 1,
        where_train: params.perfil_atleta?.where_train || [],
      },
      data_inicio_meso: params.diretrizes_plano?.data_inicio,
      ai_coach_name: params.ai_coach_name,
    });
    await admin.from('ai_generation_jobs').update({
      step_3_result: result,
      current_step: 4,
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

  } else if (step === 4) {
    console.log(`[orchestrate] new_plan step 4: gerar_detalhamento (parallel)`);
    const visaoSemanal = job.step_3_result?.visaoSemanal || [];
    const blocos = job.step_2_result?.visaoGeralPlano?.blocos || [];
    const meso1 = blocos[0] || {};
    const meso1Nome = meso1.mesociclo || 'Mesociclo 1';

    // Group by week, excluding rest days
    const weekGroups: Record<number, any[]> = {};
    for (const dia of visaoSemanal) {
      if (!dia.isDescansoAtivo) {
        const w = dia.week || 1;
        if (!weekGroups[w]) weekGroups[w] = [];
        weekGroups[w].push(dia);
      }
    }
    const weeks = Object.keys(weekGroups).map(Number).sort((a, b) => a - b);

    // Parallel LLM calls for each week
    const results = await Promise.all(weeks.map(weekNum =>
      callGerarTreino({
        acao: 'gerar_detalhamento',
        email_utilizador: params.email_utilizador,
        visao_semanal: weekGroups[weekNum],
        meso_context: {
          nome: meso1Nome,
          objetivo: params.diretrizes_plano?.objetivo || '',
          semanaNum: weekNum,
          totalSemanas: weeks.length,
          focoSemana: meso1.foco || '',
          whereTrain: params.perfil_atleta?.where_train || [],
          sessionsPerDay: params.perfil_atleta?.sessions_per_day || 1,
        },
        ai_coach_name: params.ai_coach_name,
      })
    ));

    const allExercicios = results.flatMap((r: any) => r.exerciciosDetalhados || []);

    // PERSIST: save training plan + sessions + workouts
    const planId = await persistNewPlan(job, allExercicios, admin);

    await admin.from('ai_generation_jobs').update({
      step_4_result: { exerciciosDetalhados: allExercicios },
      plan_id: planId,
      status: 'completed',
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

    console.log(`[orchestrate] new_plan COMPLETED. plan_id=${planId}, exercises=${allExercicios.length}`);
  }
}

// =========================================================
// NEXT CYCLE: Steps 1 → 2
// =========================================================
async function handleNextCycleStep(job: any, admin: any) {
  const step = job.current_step;
  const params = job.input_params;

  if (step === 1) {
    console.log(`[orchestrate] next_cycle step 1: gerar_proximo_ciclo`);

    // Identify next block from plan summary
    let planSummary: any = {};
    try { planSummary = JSON.parse(params.actual_plan_summary_json || '{}'); } catch (_e) { /* ignore */ }
    const todosOsMesos = planSummary.blocos || [];
    const mesosJaGerados: string[] = params.mesos_ja_gerados || [];
    const proximoMeso = todosOsMesos.find((b: any) => !mesosJaGerados.includes(b.mesociclo)) || {};

    // Fetch performance stats for the last cycle
    let performanceStats = null;
    const ultimoMeso = mesosJaGerados.length > 0 ? mesosJaGerados[mesosJaGerados.length - 1] : null;
    if (ultimoMeso && params.plano_id) {
      const { data } = await admin.rpc('get_mesocycle_performance_stats', {
        p_plan_id: params.plano_id,
        p_mesocycle_name: ultimoMeso,
      });
      performanceStats = data;
    }

    const result = await callGerarTreino({
      acao: 'gerar_proximo_ciclo',
      email_utilizador: params.email_utilizador,
      bloco_atual: proximoMeso,
      performance_stats: performanceStats,
      ai_coach_name: params.ai_coach_name,
    });

    await admin.from('ai_generation_jobs').update({
      step_1_result: { ...result, _blocoAtual: proximoMeso },
      current_step: 2,
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

  } else if (step === 2) {
    console.log(`[orchestrate] next_cycle step 2: gerar_detalhamento (parallel)`);
    const cicloResult = job.step_1_result || {};
    const visaoSemanal = cicloResult.visaoSemanal || [];
    const blocoAtual = cicloResult._blocoAtual || {};
    const mesoNome = blocoAtual.mesociclo || 'Próximo Meso';

    let planSummary: any = {};
    try { planSummary = JSON.parse(params.actual_plan_summary_json || '{}'); } catch (_e) { /* ignore */ }

    // Group by week
    const weekGroups: Record<number, any[]> = {};
    for (const dia of visaoSemanal) {
      if (!dia.isDescansoAtivo) {
        const w = dia.week || 1;
        if (!weekGroups[w]) weekGroups[w] = [];
        weekGroups[w].push(dia);
      }
    }
    const weeks = Object.keys(weekGroups).map(Number).sort((a, b) => a - b);

    const results = await Promise.all(weeks.map(weekNum =>
      callGerarTreino({
        acao: 'gerar_detalhamento',
        email_utilizador: params.email_utilizador,
        visao_semanal: weekGroups[weekNum],
        meso_context: {
          nome: mesoNome,
          objetivo: planSummary.objetivoPrincipal || '',
          semanaNum: weekNum,
          totalSemanas: weeks.length,
          focoSemana: blocoAtual.foco || '',
        },
        ai_coach_name: params.ai_coach_name,
      })
    ));

    const allExercicios = results.flatMap((r: any) => r.exerciciosDetalhados || []);

    // PERSIST: update training plan + save exercises
    await persistNextCycle(job, allExercicios, admin);

    await admin.from('ai_generation_jobs').update({
      step_2_result: { exerciciosDetalhados: allExercicios },
      plan_id: params.plano_id,
      status: 'completed',
      updated_at: new Date().toISOString(),
    }).eq('id', job.id);

    console.log(`[orchestrate] next_cycle COMPLETED. exercises=${allExercicios.length}`);
  }
}

// =========================================================
// Persistence: Save new plan + exercises to DB
// =========================================================
async function persistNewPlan(job: any, exercicios: any[], admin: any): Promise<string> {
  const params = job.input_params;
  const today = new Date().toISOString().split('T')[0];

  // Get user_id
  const { data: profile } = await admin
    .from('profiles').select('id').eq('email', params.email_utilizador).single();
  if (!profile?.id) throw new Error(`User not found: ${params.email_utilizador}`);

  // Clean old future AI sessions
  await admin.from('sessions').delete()
    .eq('user_email', params.email_utilizador)
    .eq('ai_coach_name', params.ai_coach_name || 'Human Coach')
    .not('plan_id', 'is', null)
    .gt('date', today);

  // Save training plan
  const { data: planRecord, error: planError } = await admin.from('training_plans').insert({
    user_id: profile.id,
    start_date: params.diretrizes_plano?.data_inicio,
    end_date: params.diretrizes_plano?.data_fim || null,
    notes: params.diretrizes_plano?.notas || null,
    competitions: (params.diretrizes_plano?.competicoes || []).map((c: string) => ({ name: c, date: null })),
    actual_plan_summary: JSON.stringify(job.step_2_result?.visaoGeralPlano || {}),
    workouts_plan_text: JSON.stringify(job.step_1_result?.analiseMacro || {}),
    workouts_plan_table: job.step_3_result?.visaoSemanal || [],
    ai_coach_name: params.ai_coach_name || 'Human Coach',
  }).select('id').single();

  if (planError) throw new Error(`Failed to save training plan: ${planError.message}`);
  const planId = planRecord?.id;

  // Save exercises
  await persistExercicios(exercicios, params.email_utilizador, planId, params.ai_coach_name, admin);
  return planId;
}

async function persistNextCycle(job: any, exercicios: any[], admin: any) {
  const params = job.input_params;
  const cicloResult = job.step_1_result || {};

  let planSummary: any = {};
  try { planSummary = JSON.parse(params.actual_plan_summary_json || '{}'); } catch (_e) { /* ignore */ }

  await admin.from('training_plans').update({
    progress_analysis: JSON.stringify(cicloResult.analiseCicloAnterior || {}),
    actual_plan_summary: JSON.stringify(planSummary),
    workouts_plan_table: [
      ...(params.current_workouts_table || []),
      ...(cicloResult.visaoSemanal || []),
    ],
  }).eq('id', params.plano_id);

  await persistExercicios(exercicios, params.email_utilizador, params.plano_id, params.ai_coach_name, admin);
}

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
        date: ex.date,
        session: ex.session,
        session_type: st,
        user_email: email,
        ...(planId ? { plan_id: planId } : {}),
        ...(aiCoachName ? { ai_coach_name: aiCoachName } : {}),
      };
    }

    records.push({
      date: ex.date, week: ex.week, mesocycle: ex.mesocycle, day: ex.day,
      session: ex.session, session_type: st, duration: ex.duration,
      workout_idx: ex.workout_idx, exercise: ex.exercise,
      exercise_title: ex.exercise_title, exercise_group: ex.exercise_group,
      exercise_type: ex.exercise_type, sets: ex.sets, details: ex.details,
      time_exercise: ex.time_exercise, ex_unit: ex.ex_unit,
      rest: ex.rest, rest_unit: ex.rest_unit,
      rest_round: ex.rest_round, rest_round_unit: ex.rest_round_unit,
      total_time: ex.total_time, location: ex.location, stage: ex.stage,
      workout_link: ex.workout_link || '', adaptacaoLesao: ex.adaptacaoLesao || '',
      user_email: email,
      date_session_sessiontype_key: sessionKey,
      wod_exercise_id: `${ex.date}_${ex.session}_${ex.workout_idx}_${Date.now() % 100000}_${i}`,
    });
  }

  const sessions = Object.values(uniqueSessions);
  if (sessions.length > 0) {
    const { error } = await admin.from('sessions').upsert(sessions, { onConflict: 'date_session_sessiontype_key' });
    if (error) console.error('[persist] sessions upsert error:', error);
  }
  if (records.length > 0) {
    const { error } = await admin.from('workouts').insert(records);
    if (error) console.error('[persist] workouts insert error:', error);
  }
  console.log(`[persist] Saved ${sessions.length} sessions + ${records.length} workouts`);
}
