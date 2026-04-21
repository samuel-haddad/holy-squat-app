import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI } from "npm:@google/generative-ai"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const allowedSessionTypes = `
Acessório, Acessórios-Blindagem, Calistenia, 
Cardio, Cardio-Mobilidade, Core, Core Strength, Core-Prep, 
Crossfit, Descanso, Endurance, EMOM, FBB, 
Força-Heavy, Força-Metcon, Força-Skill, 
Full Body Pump, Full Session, Ginástica-Metcon, 
Hipertrofia, Hipertrofia-Blindagem, 
LPO, LPO-Força-Metcon, LPO-Metcon, LPO-Potência, Metcon, 
Mobilidade, Mobilidade-Flow, Mobilidade-Cardio, Mobilidade-Core, 
Mobilidade-Inferiores, Mobilidade-Prep, Multi, Musculação, 
Musculação-Cardio, Musculação-Funcional, Musculação-Força, 
Natação, Prehab, Prehab-Força, Prehab-Mobilidade, Recuperação Ativa, 
Reintrodução-FBB, Skill, Skill-Metcon`;

const COACH_PERSONA = `Você é o AI Coach do Holy Squat App. Seu perfil: Coach Level de Crossfit, com grande conhecimento sobre reabilitação de lesões, em especial de ombro e joelho, especializado na integração do treinamento de força tradicional, com ênfase em isolamento, bodybuilding funcional e protocolos de Prehab para CrossFit. Seu foco são protocolos de Concurrent Training que buscam mitigar o "efeito de interferência" entre eles.`;

const METRICS_DEFINITIONS = `
[DICIONÁRIO E INTERPRETAÇÃO DE MÉTRICAS (KPIs)]
1. Adherence (Taxa de Adesão): % de exercícios planejados concluídos nos últimos 30 dias. 
   - Interpretação: > 90% (Alta disciplina); < 70% (Necessário reduzir volume ou ajustar rotina).
2. IFR (Índice de Força Relativa): Soma dos melhores PRs em Back Squat, Deadlift e Press dividida pelo peso corporal.
   - Interpretação: Exprime a força bruta em relação ao peso do atleta. > 5.0 (Excelente); 3.0-4.0 (Intermediário).
3. Avg_PSE (Média de Esforço Percebido): Média da escala 1-10 nos últimos 90 dias.
   - Interpretação: 8-9 (Limite/Risco de burnout); 5-6 (Manutenção/Base aeróbica).
4. Current_Workload (IEA): Volume total * Intensidade nos últimos 30 dias.
   - Interpretação: "Carga Aguda". Use para evitar aumentos bruscos que causem lesões.
5. Best_Evolution: Comparação % entre Workload atual e baseline de 6 meses.
   - Interpretação: Positivo (Overload progressivo); Negativo (Deload ou perda de consistência).
6. Weekly_Freq: Média de dias únicos treinados por semana nos últimos 30 dias.
   - Interpretação: Mede o ritmo biológico e a capacidade de recuperação (recovery).
7. Streak: Semanas consecutivas com pelo menos 3 treinos realizados.
   - Interpretação: Mede resiliência e formação de hábito. Mais valioso que o streak diário.
`;

const DATA_CONTRACT = `
[RESTRIÇÃO DE NOMENCLATURA]
- session_type: Escolha obrigatoriamente um valor desta lista: [${allowedSessionTypes}]. Proibido inventar termos.

[REGRAS DE OURO DO TEMPO (BUDGETING)]
1. Respeite a Duração (du): Se a sessão tem 60min, a soma de todos os 'tt' deve totalizar ~54min (90% do tempo). 
2. Margem de Erro: Os 10% restantes (6min para uma sessão de 60min) são reservados para transições entre blocos.
3. Distribuição Sugerida: 
   - Warmup: 10% | Skill/Strength: 40% | Workout: 40% | Cooldown: 10%.

[CONTRATO DE CAMPOS - CÁLCULO DE TT]
- ts (Sets): Número de séries/rounds. Nunca null.
- re/ru (Rest/Unit): Descanso entre séries (ex: 90, "seg").
- te/tu (Time Exercise/Unit): Tempo de execução de 1 série. Dê preferência a "seg" para séries de força (ex: 45) e "min" para cardios longos.
- tt (Total Time): Cálculo rigoroso em minutos:
  Fórmula: tt = ((time_exercise + rest) * sets) / 60.
  *Se o exercício for por tempo fixo (ex: Corrida 10min), tt = 10.*

[HEURÍSTICA DE EXECUÇÃO (Para estimar 'te')]
- Força (LPO): 5 seg por repetição. (Ex: 10 reps = 50 seg).
- Ginástica/Acessórios/Agachamentos: 3 seg por repetição. (Ex: 10 reps = 30 seg).
- Explosivos/Burpees: 2 seg por repetição.
- SEMPRE preencha 'te' e 're'. Nunca retorne 0 se houver trabalho sendo feito.
`;

const FEW_SHOT_EXAMPLES = `
[EXEMPLO DE ALTA PRECISÃO - SESSÃO 60MIN]
{"dt":"2025-05-19","dy":"Segunda","se":1,"st":"Força-Skill","du":60,"idx":1,"ex":"Back Squat","et":"Força de Pernas","eg":"Lower Body","ey":"Força","ts":4,"de":"4x8 @70% 1RM (Estimativa: 40s on / 90s off)","te":40,"eu":"seg","re":90,"ru":"seg","tt":9,"lo":"Box","sg":"strength","al":""}
{"dt":"2025-05-19","dy":"Segunda","se":1,"st":"Força-Skill","du":60,"idx":2,"ex":"Burpee Over Bar","et":"Metcon","eg":"Full Body","ey":"Condicionamento","ts":1,"de":"AMRAP 12min","te":12,"eu":"min","re":0,"ru":"seg","tt":12,"lo":"Box","sg":"workout","al":""}
`;

// =========================================================
// Helper: format training sessions for LLM
// =========================================================
function formatTrainingSessions(sessions: any[]): string {
  if (!sessions || sessions.length === 0) {
    throw new Error("Nenhuma sessão de treino configurada. Por favor, configure suas sessões no perfil ou no onboarding antes de prosseguir.");
  }
  return sessions.map((s: any) => 
    `- Sessão ${s.session_number}: Locais=[${s.locations?.join(', ')}] | Duração=${s.duration_minutes}min | Dias=[${s.schedule?.join(', ')}] | Turno=${s.time_of_day}${s.notes ? ` | Notas: ${s.notes}` : ''}`
  ).join('\n        ');
}

// =========================================================
// Helper: format the structured history summary for the LLM
// Transforms the RPC JSON output into readable text (~5k tokens
// instead of 150 raw workout records)
// =========================================================
function formatHistorySummary(summary: any): string {
  if (!summary) return "Sem histórico disponível.";
  const lines: string[] = [];

  // ── Módulo 1: Perfil mensal ──
  if (summary.monthly_profile?.length) {
    lines.push('[HISTÓRICO MENSAL — 12 MESES]');
    for (const m of summary.monthly_profile) {
      const groups = Object.entries(m.group_pct || {})
        .sort(([, a]: any, [, b]: any) => b - a)
        .slice(0, 4)
        .map(([k, v]) => `${k}: ${v}%`)
        .join(' | ');
      lines.push(`${m.month}: ${m.train_days} dias treino | ${m.sessions} sessões | ${groups || 'sem dados de grupo'}`);
    }
    lines.push('');
  }

  // ── Módulo 2: Exercícios de Força ──
  if (summary.strength_describe?.length) {
    lines.push('[EXERCÍCIOS DE FORÇA — DESCRIBE (carga aproximada, join por data)]');
    for (const ex of (summary.strength_describe as any[]).slice(0, 15)) {
      const arrow = ex.trend === 'crescente' ? '↑' : ex.trend === 'regressiva' ? '↓' : '→';
      lines.push(
        `${ex.exercise} (${ex.group}): ${ex.freq}x | ` +
        `min ${ex.load_min ?? '?'}kg / avg ${ex.load_avg ?? '?'}kg / max ${ex.load_max ?? '?'}kg | ` +
        `${arrow} ${ex.trend} | Último: ${ex.last}`
      );
    }
    lines.push('');
  }

  // ── Módulo 3: WODs / Metcons ──
  if (summary.metcon_describe?.length) {
    lines.push('[WODs / METCONS]');
    for (const ex of (summary.metcon_describe as any[]).slice(0, 15)) {
      if (ex.has_weight && ex.load_max > 0) {
        lines.push(
          `${ex.exercise} (${ex.group}): ${ex.freq}x | ` +
          `Carga: ${ex.load_min ?? '?'}–${ex.load_avg ?? '?'}–${ex.load_max ?? '?'}kg [WOD com carga]`
        );
      } else if (ex.avg_cardio > 0) {
        lines.push(
          `${ex.exercise} (${ex.group}): ${ex.freq}x | ` +
          `Resultado médio: ${ex.avg_cardio} ${ex.cardio_unit || ''} [Cardio/Endurance]`
        );
      } else {
        const reps = ex.avg_reps > 0 ? ` | Média reps: ${ex.avg_reps}` : '';
        lines.push(`${ex.exercise} (${ex.group}): ${ex.freq}x | Sem log de carga/cardio${reps}`);
      }
    }
    lines.push('');
  }

  // ── Módulo 4: Top 15 por frequência ──
  if (summary.top_exercises?.length) {
    lines.push('[TOP 15 EXERCÍCIOS — FREQUÊNCIA (todos os estágios menos warm/cool)]');
    for (const ex of summary.top_exercises) {
      lines.push(`${ex.exercise} (${ex.group} | ${ex.type}): ${ex.freq}x | Último: ${ex.last}`);
    }
    lines.push('');
  }

  // ── Módulo 5: Progressão trimestral ──
  if (summary.quarterly_progression?.length) {
    lines.push('[PROGRESSÃO TRIMESTRAL — LEVANTAMENTOS-CHAVE]');
    for (const ex of summary.quarterly_progression) {
      const qStr = (ex.quarters || []).map((q: any) => `${q.q}: avg ${q.avg}kg / max ${q.max}kg`).join(' → ');
      lines.push(`${ex.exercise}: ${qStr}`);
    }
  }

  return lines.join('\n');
}

// =========================================================
// Helper: generate content with the correct provider (Google or Anthropic)
// =========================================================
async function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function generateWithProvider(
  prompt: string,
  provider: string,
  llmModel: string,
  genAI: any,
  actionLabel: string,
  maxTokens: number = 16000
): Promise<any> {
  const targetTemperature = provider === 'anthropic' ? 0.2 : 0.7; // Optimized for structural JSON speed
  const maxRetries = 3;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (provider === 'google') {
        const model = genAI.getGenerativeModel(
          { model: llmModel, generationConfig: { temperature: targetTemperature, maxOutputTokens: maxTokens } },
          { apiVersion: 'v1beta' }
        );
        const result = await model.generateContent([prompt]);
        const usage = result.response.usageMetadata;
        console.log(`[TOKENS] ${actionLabel} | model: ${llmModel} | input: ${usage?.promptTokenCount ?? '?'} | output: ${usage?.candidatesTokenCount ?? '?'}`);
        
        let rawText = result.response.text();
        if (rawText.startsWith('```')) {
          rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
        }
        return JSON.parse(rawText);

      } else if (provider === 'anthropic') {
        console.log(`[anthropic] Calling ${llmModel} (maxTok: ${maxTokens})`);
        const response = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': Deno.env.get('ANTHROPIC_API_KEY') ?? '',
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify({
            model: llmModel,
            max_tokens: maxTokens,
            temperature: targetTemperature,
            system: "You are an AI CrossFit Coach. ALWAYS respond with PURE VALID JSON ONLY. No markdown, no pre-amble, no post-amble. Prohibited: Trailing commas in arrays/objects. Keys must be double-quoted.",
            messages: [{ role: 'user', content: prompt }],
          }),
        });
        
        const data = await response.json();
        if (!response.ok) {
          // If it's a rate limit error (429), throw it so it can be retried
          if (response.status === 429) {
            throw new Error(`429: ${JSON.stringify(data)}`);
          }
          throw new Error(`Anthropic API error (${response.status}): ${JSON.stringify(data)}`);
        }

        const stopReason = data.stop_reason;
        console.log(`[TOKENS] ${actionLabel} | model: ${llmModel} | maxTok: ${maxTokens} | input: ${data.usage?.input_tokens} | output: ${data.usage?.output_tokens} | stop: ${stopReason}`);

        let rawText: string = data.content[0].text.trim();
        if (rawText.startsWith('```')) {
          rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
        }
        rawText = rawText.replace(/,\s*([\}\]])/g, '$1');

        try {
          return JSON.parse(rawText);
        } catch (e: any) {
          console.error(`[JSON ERROR] Falha ao parsear resposta do Claude em ${actionLabel}`);
          throw new Error(`Invalid JSON from Claude at ${actionLabel}: ${e.message}`);
        }

      } else {
        throw new Error(`Provider desconhecido: ${provider}`);
      }

    } catch (err: any) {
      const errorText = err.message || '';
      const isRateLimit = errorText.includes('429') || errorText.toLowerCase().includes('quota') || errorText.toLowerCase().includes('limit');
      
      if (isRateLimit && attempt < maxRetries) {
        const delay = attempt * 3500; // 3.5s, 7s...
        console.warn(`[RETRY] Rate limit (429) detectado em ${actionLabel}. Tentativa ${attempt}/${maxRetries}. Aguardando ${delay}ms...`);
        await sleep(delay);
        continue;
      }
      // If it's not a rate limit or we're out of retries, throw the error
      throw err;
    }
  }
}

async function getEmbedding(text: string) {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${apiKey}`;

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "models/gemini-embedding-001",
      content: { parts: [{ text }] },
      outputDimensionality: 768
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Erro no Embedding: ${JSON.stringify(error)}`);
  }

  const data = await response.json();
  return data.embedding.values;
}

// =========================================================
// Helper: query the knowledge base (always Google Embeddings)
// =========================================================
async function queryKnowledgeBase(queryText: string, genAI: any, adminClient: any) {
  if (!queryText) return "";
  try {
    const embedding = await getEmbedding(queryText);
    const { data: documents, error } = await adminClient.rpc('match_knowledge_base', {
      query_embedding: embedding,
      match_threshold: 0.4,
      match_count: 5
    });
    if (error) { console.error("RPC Error (match_knowledge_base):", error); return ""; }
    if (documents && documents.length > 0) {
      return `\n[LITERATURA CIENTÍFICA]\n${documents.map((d: any) => d.content).join("\n---\n")}\n`;
    }
    return "";
  } catch (err) {
    console.error("Error querying knowledge base:", err);
    return "";
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Anon client used for user-scoped queries (profiles, technique_feedbacks, etc.)
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    // Admin client used for RPCs that require service role (called internally by orchestrator
    // which passes its service role key as Authorization, bypassing RLS correctly)
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const payload = await req.json()
    const { acao, ai_coach_name } = payload

    // ── Always instantiate genAI for embeddings (knowledge base) ──
    const genAI = new GoogleGenerativeAI(Deno.env.get('GEMINI_API_KEY')!)
    const today = new Date().toISOString().split('T')[0];

    // ── Fetch coach configuration from ai_coach table ────────────
    let provider = 'google';
    let llmModel = 'gemini-pro-latest';

    if (ai_coach_name) {
      const { data: coachData, error: coachError } = await adminClient
        .from('ai_coach')
        .select('llm_model, provider')
        .eq('ai_coach_name', ai_coach_name)
        .single();

      if (coachError || !coachData) {
        console.warn(`Coach '${ai_coach_name}' não encontrado. Usando Gemini padrão.`);
      } else {
        provider = coachData.provider;
        llmModel = coachData.llm_model;
        console.log(`Coach: ${ai_coach_name} | Model: ${llmModel} | Provider: ${provider}`);
      }
    }

    // =========================================================
    // ACTION 1: gerar_analise_historica
    // Analyzes the athlete's sports history.
    // OPTIMIZATION: raw workout/log dumps replaced by structured
    // RPC aggregation (~5k tokens vs ~50k previously).
    // =========================================================
    if (acao === 'gerar_analise_historica') {
      const { email_utilizador, user_id } = payload;
      if (!email_utilizador && !user_id) throw new Error("Parâmetros email_utilizador ou user_id ausentes.");
      console.log(`[Action 1] Iniciando para ${email_utilizador || user_id}`);

      // Parallel DB fetches — lean column selection, capped limits
      const profileQuery = user_id 
        ? supabaseClient.from('profiles').select('*').eq('id', user_id).single()
        : supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const [profileRes, prRes, benchRes] = await Promise.all([
        profileQuery,
        // Correct columns: 'pr' and 'pr_unit' (NOT 'value'/'unit' which don't exist)
        adminClient.from('pr_log')
          .select('exercise, pr, pr_unit, date')
          .eq('user_email', email_utilizador)
          .order('date', { ascending: false })
          .limit(100),  // fetch all to compute max per exercise below
        // Correct columns: 'exercise', 'result', 'date' (NOT 'benchmark_name'/'result_unit'/'logged_at')
        adminClient.from('benchmarks_logs')
          .select('exercise, result, date')
          .order('date', { ascending: false })
          .limit(50)
      ]);

      const profile = profileRes.data || {};
      const userWeight = Number(profile.weight) || 0;

      // Now call RPC with weight after fetching profile
      console.time('[perf] rpc_planning_stats');
      const athleteStatsRes = await adminClient.rpc('get_athlete_planning_stats', { 
        p_email: email_utilizador,
        p_user_weight: userWeight
      });
      console.timeEnd('[perf] rpc_planning_stats');

      if (athleteStatsRes.error) {
        console.warn('[RPC] get_athlete_planning_stats error:', athleteStatsRes.error);
      } else {
        const statsDataCheck = Array.isArray(athleteStatsRes.data) ? athleteStatsRes.data[0] : athleteStatsRes.data;
        console.log('[RPC] get_athlete_planning_stats OK. kpis keys:', Object.keys(statsDataCheck?.kpis || {}));
      }

      const statsRaw = athleteStatsRes?.data;
      const statsObj = Array.isArray(statsRaw) ? statsRaw[0] : statsRaw;
      const athleteStats = payload.athlete_stats_summary || (statsObj?.kpis) || {};

      // Aggregate PRs: keep only the MAX value per exercise (as the athlete's all-time best)
      const prByExercise: Record<string, any> = {};
      for (const row of (prRes.data || [])) {
        const ex = row.exercise;
        const val = Number(row.pr) || 0;
        if (!prByExercise[ex] || val > Number(prByExercise[ex].pr)) {
          prByExercise[ex] = row;
        }
      }
      const prMaxPerExercise = Object.values(prByExercise)
        .sort((a: any, b: any) => a.exercise.localeCompare(b.exercise));
      console.log(`[prs] ${prMaxPerExercise.length} unique exercises with PRs`);

      // Benchmarks: one row per exercise (already unique by exercise in the table)
      const benchData = benchRes.data || [];
      console.log(`[benchmarks] ${benchData.length} benchmark records`);

      // ── Structured history summary (prefer RPC, direct-query fallback if empty) ──
      // CRITICAL: use adminClient — supabaseClient fails RLS when called from orchestrator
      //           (the Authorization header carries service role key, not a user JWT)
      console.time('[perf] rpc_history_summary');
      const { data: historySummaryRaw, error: histErr } = await adminClient
        .rpc('get_athlete_history_summary', { p_email: email_utilizador });
      console.timeEnd('[perf] rpc_history_summary');

      if (histErr) {
        console.error('[RPC] get_athlete_history_summary FAILED:', JSON.stringify(histErr));
      } else {
        // Defensive check: RPC may return an array instead of an object on some Supabase versions
        const rpcData = Array.isArray(historySummaryRaw) ? historySummaryRaw[0] : historySummaryRaw;
        console.log(
          '[RPC] get_athlete_history_summary result check:',
          'monthly_profile:', rpcData?.monthly_profile?.length ?? 'missing',
          'top_exercises:', rpcData?.top_exercises?.length ?? 'missing',
          'strength_describe:', rpcData?.strength_describe?.length ?? 'missing'
        );
      }

      const rpcPayload = Array.isArray(historySummaryRaw) ? historySummaryRaw[0] : historySummaryRaw;
      let historySummaryText = formatHistorySummary(rpcPayload);
      const rpcProducedContent = historySummaryText.length > 60; // true if RPC gave real data

      // ── Direct-query fallback when RPC returns empty/null ──
      // Queries workouts_logs + workouts directly, no RPC dependency.
      if (!rpcProducedContent) {
        console.warn('[fallback-history] RPC returned empty. Building history from direct queries...');
        const sixMonthsAgo = new Date(Date.now() - 183 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

        const [logsRes, workoutsRes] = await Promise.all([
          adminClient
            .from('workouts_logs')
            .select('workout_date, pse, weight, weight_unit, wod_exercise_id')
            .eq('user_email', email_utilizador)
            .eq('done', 1)
            .gte('workout_date', sixMonthsAgo)
            .not('workout_date', 'is', null)
            .order('workout_date', { ascending: false })
            .limit(800),
          adminClient
            .from('workouts')
            .select('wod_exercise_id, exercise, exercise_group, exercise_type, stage')
            .eq('user_email', email_utilizador)
            .gte('date', sixMonthsAgo)
            .limit(800),
        ]);

        const rawLogs = logsRes.data || [];
        const rawWorkouts = workoutsRes.data || [];
        console.log(`[fallback-history] logs: ${rawLogs.length}, workouts: ${rawWorkouts.length}`);

        // Build wod_exercise_id → exercise info map
        const wodMap: Record<string, any> = {};
        for (const w of rawWorkouts) wodMap[w.wod_exercise_id] = w;

        // Monthly activity stats
        const byMonth: Record<string, { sessions: Set<string>; pseSums: number[]; exercises: Map<string, number> }> = {};
        for (const log of rawLogs) {
          const month = String(log.workout_date).substring(0, 7);
          if (!byMonth[month]) byMonth[month] = { sessions: new Set(), pseSums: [], exercises: new Map() };
          byMonth[month].sessions.add(String(log.workout_date));
          const pse = parseFloat(log.pse);
          if (!isNaN(pse) && pse > 0) byMonth[month].pseSums.push(pse);
          const wod = wodMap[log.wod_exercise_id];
          if (wod?.exercise && wod.stage !== 'warmup' && wod.stage !== 'cooldown') {
            const cnt = byMonth[month].exercises.get(wod.exercise) || 0;
            byMonth[month].exercises.set(wod.exercise, cnt + 1);
          }
        }

        const monthLines: string[] = ['[HISTÓRICO DE ATIVIDADE — Últimos 6 meses (query direta)]'];
        for (const [month, stats] of Object.entries(byMonth).sort(([a], [b]) => b.localeCompare(a))) {
          const days = stats.sessions.size;
          const avgPse = stats.pseSums.length > 0
            ? (stats.pseSums.reduce((a, b) => a + b, 0) / stats.pseSums.length).toFixed(1)
            : 'N/A';
          const topEx = [...stats.exercises.entries()]
            .sort((a, b) => b[1] - a[1]).slice(0, 5)
            .map(([ex, cnt]) => `${ex}(${cnt}x)`).join(', ');
          monthLines.push(`${month}: ${days} dias treino | PSE médio: ${avgPse} | Exercícios freq.: ${topEx || 'n/a'}`);
        }

        // Exercise frequency table
        const exFreq: Map<string, { group: string; type: string; count: number; lastDate: string }> = new Map();
        for (const log of rawLogs) {
          const wod = wodMap[log.wod_exercise_id];
          if (wod?.exercise && wod.stage !== 'warmup' && wod.stage !== 'cooldown') {
            const key = wod.exercise;
            const cur = exFreq.get(key) || { group: wod.exercise_group || '', type: wod.exercise_type || '', count: 0, lastDate: '' };
            cur.count++;
            if (!cur.lastDate || String(log.workout_date) > cur.lastDate) cur.lastDate = String(log.workout_date);
            exFreq.set(key, cur);
          }
        }
        const topExercicios = [...exFreq.entries()]
          .sort((a, b) => b[1].count - a[1].count).slice(0, 15);
        if (topExercicios.length > 0) {
          monthLines.push('');
          monthLines.push('[TOP EXERCÍCIOS — FREQUÊNCIA (Últimos 6 meses)]');
          for (const [ex, info] of topExercicios) {
            monthLines.push(`${ex} (${info.group} | ${info.type}): ${info.count}x | Último: ${info.lastDate}`);
          }
        }

        historySummaryText = monthLines.join('\n');
        console.log(`[fallback-history] Built. Months: ${Object.keys(byMonth).length}, exercises: ${topExercicios.length}`);
      }

      // ── IFR: compute from PR data (fallback for DB fn which has type-mismatch on numeric col or returns 0) ──
      // The SQL casts NULLIF(pr,'') which fails when pr is NUMERIC. We sum max PRs of key exercises.
      const IFR_EXERCISE_KEYWORDS = ['back squat', 'deadlift', 'shoulder press', 'strict press', 'overhead press'];
      const ifrSumFromPRs = prMaxPerExercise
        .filter((r: any) => IFR_EXERCISE_KEYWORDS.some(k => r.exercise?.toLowerCase().includes(k)))
        .reduce((sum: number, r: any) => {
          // Defensive parsing: remove non-numeric chars (except .) to handle "6+10" style strings
          const cleanPR = String(r.pr || '0').replace(/[^0-9.]/g, '');
          let val = Number(cleanPR) || 0;
          if (['lb', 'lbs', 'libra', 'libras'].includes(String(r.pr_unit).toLowerCase().trim())) {
            val = val * 0.453592;
          }
          return sum + val;
        }, 0);
      const computedIfr = userWeight > 0 ? Number((ifrSumFromPRs / userWeight).toFixed(2)) : 0;
      const effectiveIfr = (athleteStats.ifr && athleteStats.ifr > 0)
        ? athleteStats.ifr
        : computedIfr;
      console.log(`[ifr] DB: ${athleteStats.ifr}, computed: ${computedIfr}, using: ${effectiveIfr}`);

      // ── Training sessions: prefer payload (forwarded by orchestrator), DB as fallback ──
      let trainingSessions: any[] = [];
      if (payload.training_sessions && payload.training_sessions.length > 0) {
        trainingSessions = payload.training_sessions;
        console.log(`[sessions] Using ${trainingSessions.length} sessions from payload`);
      } else {
        const sessionFilter = user_id ? { user_id } : (profile.id ? { user_id: profile.id } : null);
        if (sessionFilter) {
          const { data: sessionsData } = await supabaseClient
            .from('training_sessions')
            .select('session_number, locations, duration_minutes, schedule, time_of_day, notes')
            .eq('user_id', sessionFilter.user_id)
            .order('session_number', { ascending: true });
          trainingSessions = sessionsData || [];
          console.log(`[sessions] DB fallback returned ${trainingSessions.length} sessions for user_id=${sessionFilter.user_id}`);
        }
      }

      // ── Technique feedbacks ──
      let techniqueFeedbacksStr = "Nenhum feedback de técnica registrado.";
      if (profile?.id) {
        const { data: tfData } = await supabaseClient
          .from('technique_feedbacks')
          .select('exercise_name, resume_text, improve_exercises')
          .eq('user_id', profile.id)
          .order('created_at', { ascending: false })
          .limit(15);
        if (tfData && tfData.length > 0) {
          techniqueFeedbacksStr = tfData.map((tf: any) =>
            `- Exercício: ${tf.exercise_name}\n  Análise: ${tf.resume_text}\n  Recomendação (Correção): ${JSON.stringify(tf.improve_exercises)}`
          ).join('\n');
        }
      }

      // ── RAG: knowledge base ──
      console.time('[perf] rag_query');
      const ragQuery = `${profile.about_me || ''} ${profile.skills_training || ''} ${profile.lesoes || ''}`;
      const knowledgeContext = await queryKnowledgeBase(ragQuery, genAI, adminClient);
      console.timeEnd('[perf] rag_query');

      const prompt = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]

        [MISSÃO — ANÁLISE DO HISTÓRICO ESPORTIVO]
        Analise detalhadamente o histórico do atleta abaixo. Não se limite a resumir logs; você deve 
        interpretar a trajetória do atleta. 
        
        [HIERARQUIA DE ANÁLISE - PRIORIDADE DE DADOS]
        1. MARCAS ABSOLUTAS: PRs e Benchmarks são as suas "âncoras de verdade". Use-os para validar se os treinos recentes estão de acordo com a capacidade real do atleta.
        2. MÉTRICAS DERIVADAS: Utilize o IFR (baseado nos PRs) para avaliar a força relativa por KG.
        3. TENDÊNCIA DE CARGA: Observe se a 'Evolution' e 'Workload' corroboram os recordes ou se há um platô.

        [CONTEXTO CIENTÍFICO (RAG)]
        ${knowledgeContext}

        [DICIONÁRIO DE MÉTRICAS]
        ${METRICS_DEFINITIONS}

        [KPIs DETERMINÍSTICOS DO ATLETA]
        - Aderência Global: ${athleteStats.adherence}%
        - PSE Médio (90 dias): ${athleteStats.avg_pse}
        - IFR (Índice de Força Relativa): ${effectiveIfr}${effectiveIfr !== athleteStats.ifr ? ' (calculado dos PRs registrados)' : ''}
        - Evolução de Esforço: ${athleteStats.best_evolution?.percent}% vs baseline 6 meses
        - Streak Atual: ${athleteStats.streak} semanas
        - Frequência Semanal: ${athleteStats.weekly_freq} treinos/semana

        [PERFIL DO ATLETA]
        - Nome: ${profile.name}
        - Peso Corporal: ${userWeight} kg
        - About: ${profile.about_me || 'Não informado'}
        - Skills: ${profile.skills_training || 'Não informado'}
        - Lesões: ${profile.lesoes || 'Nenhuma registrada'}

        [AVALIAÇÃO BIOMECÂNICA E TÉCNICA (TECHNIQUE FEEDBACK)]
        O atleta realizou testes de biomecânica usando IA. Aqui estão os feedbacks mais recentes:
        ${techniqueFeedbacksStr}
        *DIRETRIZ: Mencione essas deficiências na sua análise e recomende a correção rigorosa nas etapas de Skill e Prehab.*

        [SESSÕES DE TREINO DISPONÍVEIS]
        ${formatTrainingSessions(trainingSessions)}

        [PRs DE FORÇA — MELHOR MARCA POR EXERCÍCIO]
        *DIRETRIZ: Se houver dados abaixo, eles DEVEM fundamentar sua análise de força. O IFR de ${effectiveIfr.toFixed(2)} é reflexo destes levantamentos.*
        ${prMaxPerExercise.length > 0
          ? prMaxPerExercise.map((r: any) => `- ${r.exercise}: ${r.pr} ${r.pr_unit || 'kg'} (${r.date})`).join('\n        ')
          : 'Nenhum PR registrado.'}

        [BENCHMARKS FUNCIONAIS — RESULTADOS MAIS RECENTES]
        *DIRETRIZ: Use estes benchmarks para avaliar a capacidade metabólica e técnica de Crossfit do atleta.*
        ${benchData.length > 0
          ? benchData.map((b: any) => `- ${b.exercise}: ${b.result} (${b.date || 'data não registrada'})`).join('\n        ')
          : 'Nenhum benchmark registrado.'}

        [HISTÓRICO AGREGADO — 12 MESES]
        (Dados por mês, exercício e tipo. Fonte: ${rpcProducedContent ? 'RPC get_athlete_history_summary' : 'query direta workouts_logs + workouts'})
        ${historySummaryText || 'Nenhum dado de treino encontrado nos últimos 6 meses.'}

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "analiseMacro": {
            "analise": "string — análise detalhada do histórico esportivo, pontos fortes, fracos e recomendações",
            "historico": {
              "texto": "string — resumo narrativo da evolução do atleta",
              "graficos": [
                { "tipo": "linha|barra", "titulo": "string", "dados": [{ "x": "string", "y": 0 }] }
              ]
            }
          }
        }
      `;

      console.log(`gerar_analise_historica | coach: ${ai_coach_name ?? 'default'} | prompt length: ${prompt.length}`);
      console.time('[perf] llm_generation');
      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'gerar_analise_historica', 8000);
      console.timeEnd('[perf] llm_generation');

      // Only include athlete_stats_snapshot if the RPC returned real data.
      // An empty object {} would make Flutter think stats are available but
      // render nothing (kpis/radar/heatmap keys missing). Use null so Flutter
      // shows the correct "não disponível" message instead.
      const statsData = athleteStatsRes?.data;
      const hasValidStats = statsData && statsData.kpis && statsData.radar !== undefined;

      const responseBody = {
        ...result,
        athlete_stats_snapshot: hasValidStats ? statsData : null
      };

      return new Response(JSON.stringify(responseBody), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    // =========================================================
    // ACTION 2: criar_plano
    // Projects the macrocycle blocks. Receives analysis from Action 1.
    // =========================================================
    else if (acao === 'criar_plano') {
      const {
        email_utilizador,
        user_id,
        analise_historica,
        diretrizes_plano,
        training_sessions,
      } = payload;
      console.log(`[Action 2] Iniciando para ${email_utilizador || user_id}`);

      // Self-fetch profile from DB for safety/completeness
      const profileQuery = user_id 
        ? supabaseClient.from('profiles').select('*').eq('id', user_id).single()
        : supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const { data: profileDb } = await profileQuery;

      const profile = profileDb || {};
      const analise = analise_historica || {};
      const sessions = training_sessions || [];

      const prompt = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]

        [MISSÃO — PROJETAR BLOCOS DO MACROCICLO]
        Com base na análise do histórico (fornecida abaixo), projete um macrociclo completo dividido 
        em mesociclos. Defina nome, duração em semanas e foco de cada bloco.

        [HIERARQUIA DE PRIORIDADE - LEI ZERO]
        1. SEGURANÇA E LESÕES: O usuário tem histórico em ${profile.lesoes}. Foco em Prehab e proteção tendínea.
        2. COMPETIÇÕES: Respeite rigorosamente as datas de início e fim das competições. O treinamento deve convergir para o pico de performance nessas datas e incluir Tapering adequado nas semanas que as antecedem.
        3. NOMENCLATURA: Use apenas os session_type da lista oficial: [${allowedSessionTypes}]

        [ANÁLISE DO HISTÓRICO (resultado da etapa anterior)]
        ${JSON.stringify(analise)}

        [PERFIL DO ATLETA]
        - Nome: ${profile.name}
        - About: ${profile.about_me || 'Não informado'}
        - Skills: ${profile.skills_training || 'Não informado'}
        - Lesões: ${profile.lesoes || 'Nenhuma registrada'}

        [SESSÕES DE TREINO DISPONÍVEIS]
        ${formatTrainingSessions(sessions)}

        [DIRETRIZES DO PLANO]
        - Objetivo: ${diretrizes_plano?.objetivo}
        - Início: ${diretrizes_plano?.data_inicio} | Fim: ${diretrizes_plano?.data_fim}
        - Competições: ${JSON.stringify(diretrizes_plano?.competicoes)}
        - Notas: ${diretrizes_plano?.notas}

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "visaoGeralPlano": {
            "objetivoPrincipal": "string",
            "duracaoSemanas": 0,
            "fases": [{ "nome": "string", "duracao": "string", "foco": "string" }],
            "blocos": [
              { "mesociclo": "string — ex: Meso 1 — Adaptação", "duracaoSemanas": 4, "foco": "string" }
            ]
          }
        }
      `;

      console.log(`criar_plano | coach: ${ai_coach_name ?? 'default'} | prompt length: ${prompt.length}`);
      console.time('[perf] llm_generation_step2');
      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'criar_plano', 8000);
      console.timeEnd('[perf] llm_generation_step2');
      return new Response(JSON.stringify(result), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    // =========================================================
    // ACTION 3: gerar_proximo_ciclo
    // Generates the weekly calendar for a specific mesocycle.
    // =========================================================
    else if (acao === 'gerar_proximo_ciclo') {
      const {
        email_utilizador,
        user_id,
        bloco_atual,
        performance_stats,
        cycle_snapshot,
        training_sessions,
        data_inicio_meso,
        contexto_macrociclo,
      } = payload;

      // Fetch profile from DB for session structure
      const profileQuery = user_id 
        ? supabaseClient.from('profiles').select('*').eq('id', user_id).single()
        : supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const { data: profileDb } = await profileQuery;

      const profile = profileDb || {};
      const bloco = bloco_atual || {};
      const perfStats = performance_stats || {};
      const cycleSnap = cycle_snapshot || null;
      const sessions = training_sessions || [];
      const macroCtx = contexto_macrociclo || {};

      let techniqueFeedbacksStr = "Nenhum feedback de técnica registrado.";
      if (profile?.id) {
        const { data: tfData } = await supabaseClient
          .from('technique_feedbacks')
          .select('exercise_name, resume_text, improve_exercises')
          .eq('user_id', profile.id)
          .order('created_at', { ascending: false })
          .limit(15);
        if (tfData && tfData.length > 0) {
          techniqueFeedbacksStr = tfData.map((tf: any) => 
            `- Exercício: ${tf.exercise_name}\n  Análise: ${tf.resume_text}\n  Recomendação (Correção): ${JSON.stringify(tf.improve_exercises)}`
          ).join('\n');
        }
      }

      const prompt = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]

        [MISSÃO — GERAR CALENDÁRIO SEMANAL DO MESOCICLO]
        Gere o calendário semanal completo para o mesociclo especificado abaixo.
        Se houver estatísticas do ciclo anterior, faça uma análise motivacional e técnica.

        [RESTRIÇÕES DE VERBOSIDADE - CRÍTICO PARA EVITAR TIMEOUT]
        - analiseCicloAnterior.texto: Máximo 80 palavras. Linguagem direta e técnica.
        - focoPrincipal: Máximo 6 palavras por sessão.
        - Não adicione textos fora do JSON.

        [CONTEXTO DO MACROCICLO — MEMÓRIA DAS ETAPAS ANTERIORES]
        Use as informações abaixo para manter coerência com o planejamento original:
        - Análise Histórica do Atleta: ${JSON.stringify(macroCtx.analise_historica || 'Não fornecida')}
        - Visão Geral do Plano: ${JSON.stringify(macroCtx.visao_geral_plano || 'Não fornecida')}
        - COMPETIÇÕES: ${JSON.stringify(macroCtx.competicoes || [])} (Respeite rigorosamente estas datas para pico de performance e tapering).

        [SESSÕES CONFIGURADAS - REGRAS MANDATÓRIAS]
        ${formatTrainingSessions(sessions)}
        
        REGRAS DE OURO PARA O CALENDÁRIO:
        1. Respeite os dias da semana (schedule) de cada sessão cadastrada.
        2. Use EXATAMENTE a 'Duração' configurada para cada sessão como o campo 'du'.
        3. Use os 'Locais' permitidos de cada sessão como o campo 'lo'.
        4. Se houver mais de uma sessão no mesmo dia (ex: Manhã e Tarde), gere objetos diferentes no JSON para cada sessão, identificando-as pelo 'se' (session_number).
        5. Se um dia não houver nenhuma sessão configurada, retorne 'st': 'Descanso' para esse dia.
        6. *NOTA: Nunca prescreva treinos em DUPLA ou PARTNER WODs. O treino é individual.*

        [BLOCO ATUAL DO MESOCICLO]
        - Nome: ${bloco.mesociclo}
        - Duração: ${bloco.duracaoSemanas} semanas
        - Foco: ${bloco.foco}
        - Data início do meso: ${data_inicio_meso || today}

        [ATLETA]
        - Nome: ${profile.name}

        [AVALIAÇÃO BIOMECÂNICA E TÉCNICA (TECHNIQUE FEEDBACK)]
        ${techniqueFeedbacksStr}
        *IMPORTANTE: Adapte o planejamento para focar na correção dessas deficiências técnicas.*

        [DICIONÁRIO DE MÉTRICAS]
        ${METRICS_DEFINITIONS}

        [KPIs TÉCNICOS DO CICLO ANTERIOR — get_mesocycle_performance_stats]
        (Taxa de conclusão, delta de carga, tipos negligenciados, recuperação de PRs, gráficos semanais)
        ${JSON.stringify(perfStats)}
        (Se os dados acima estiverem vazios ou zerados, o atleta não treinou ou não registrou logs.
         Nesse caso, analiseCicloAnterior.texto deve dizer que não há dados de progresso para este ciclo.)

        [KPIs GERAIS DO ATLETA — SNAPSHOT DO PERÍODO DO CICLO ENCERRADO]
        (Use as definições do DICIONÁRIO acima para interpretar estes valores)
        ${cycleSnap ? JSON.stringify(cycleSnap.kpis) : 'Sem dados disponíveis.'}
        (Use estes KPIs para calibrar a intensidade e o volume do próximo ciclo.
         Aderência < 70%: reduza volume. PSE Médio > 8: inclua semana de deload.)

        [REGRAS DE CALENDÁRIO]
        - week = intra-mesociclo (começa em 1).
        - mesocycle = "${bloco.mesociclo}".
        - ANO: ${today.split('-')[0]}.
        - session_type: Use APENAS valores de [${allowedSessionTypes}].
        - isDescansoAtivo: true para dias de repouso.

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "analiseCicloAnterior": {
            "aderencia": "string — porcentagem ou 'N/A'",
            "evolucao": "string — pontos de evolução observados",
            "texto": "string — análise motivacional e técnica baseada nos KPIs"
          },
          "visaoGeralCiclo": [
            { "semana": 1, "foco": "string", "seg": "string", "ter": "string", "qua": "string", "qui": "string", "sex": "string", "sab": "string", "dom": "string" }
          ],
          "visaoSemanal": [
            {
              "date": "YYYY-MM-DD",
              "session": 1,
              "session_type": "string",
              "focoPrincipal": "string",
              "isDescansoAtivo": false
            }
          ]
        }
        
        [REGRAS DE CONTEÚDO]
        - focoPrincipal: Máximo 5 palavras. Seja telegráfico.
        - analiseCicloAnterior.texto: Máximo 80 palavras.
        - Não retorne day, week ou mesocycle (serão injetados por fora).
      `;

      console.log(`gerar_proximo_ciclo | meso: ${bloco.mesociclo} | coach: ${ai_coach_name ?? 'default'}`);
      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'gerar_proximo_ciclo', 8000);

      // RE-INJECTION logic: Fill the derived fields to save LLM tokens and prevent timeout
      if (result.visaoSemanal && Array.isArray(result.visaoSemanal)) {
        const diasSemana = ["Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado"];
        
        result.visaoSemanal = result.visaoSemanal.map((dia: any) => {
          const d = new Date(dia.date + 'T12:00:00Z'); // mid-day to avoid TZ issues
          const dayName = diasSemana[d.getUTCDay()];
          
          // Calculate week within meso based on data_inicio_meso
          let weekNum = 1;
          if (data_inicio_meso) {
            const startD = new Date(data_inicio_meso + 'T12:00:00Z');
            const diffMs = d.getTime() - startD.getTime();
            if (diffMs > 0) {
              weekNum = Math.floor(diffMs / (7 * 24 * 60 * 60 * 1000)) + 1;
            }
          }

          return {
            ...dia,
            day: dayName,
            mesocycle: bloco.mesociclo,
            week: weekNum
          };
        });
      }

      return new Response(JSON.stringify(result), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    // =========================================================
    // ACTION 4: gerar_detalhamento
    // Fills the exercise matrix for one week using short keys.
    // =========================================================
    else if (acao === 'gerar_detalhamento') {
      const {
        email_utilizador,
        user_id,
        visao_semanal,
        meso_context,
      } = payload;

      const ctx = meso_context || {};
      
      let techniqueFeedbacksStr = "Nenhum feedback de técnica registrado.";
      if (user_id || email_utilizador) {
        const profileQuery = user_id 
          ? supabaseClient.from('profiles').select('id').eq('id', user_id).single()
          : supabaseClient.from('profiles').select('id').eq('email', email_utilizador).single();

        const { data: profileDb } = await profileQuery;
        if (profileDb?.id) {
          const { data: tfData } = await supabaseClient
            .from('technique_feedbacks')
            .select('exercise_name, resume_text, improve_exercises')
            .eq('user_id', profileDb.id)
            .order('created_at', { ascending: false })
            .limit(15);
          if (tfData && tfData.length > 0) {
            techniqueFeedbacksStr = tfData.map((tf: any) => 
              `- Exercício Original: ${tf.exercise_name}\n  Problema/Resumo: ${tf.resume_text}\n  Exercícios Corretivos Recomendados: ${JSON.stringify(tf.improve_exercises)}`
            ).join('\n');
          }
        }
      }

      const diasArr = visao_semanal || [];
      const diasStr = diasArr
        .map((d: any) => `  - ${d.date} (${d.day}) | session ${d.session || 1} | ${d.session_type} | ${d.focoPrincipal} | semana ${d.week}`)
        .join('\n');

      // RAG: query knowledge base for exercise recommendations
      const ragQuery = `${ctx.focoSemana || ''} ${ctx.objetivo || ''} exercícios crossfit`;
      const knowledgeContext = await queryKnowledgeBase(ragQuery, genAI, adminClient);

      const prompt = `
        ${COACH_PERSONA} Gere os exercícios para a Semana ${ctx.semanaNum} de ${ctx.totalSemanas} do mesociclo "${ctx.nome}".
        [DATA DE HOJE: ${today}]

        [CONTEXTO CIENTÍFICO (RAG)]
        ${knowledgeContext}

        ${DATA_CONTRACT}
        ${FEW_SHOT_EXAMPLES}

        [CONTEXTO]
        - Objetivo: ${ctx.objetivo}
        - Mesociclo: ${ctx.nome} | Semana ${ctx.semanaNum}/${ctx.totalSemanas}
        - Foco: ${ctx.focoSemana || 'Conforme planejamento'}

        [AVALIAÇÃO BIOMECÂNICA E TÉCNICA (TECHNIQUE FEEDBACK)]
        ${techniqueFeedbacksStr}
        *CRÍTICO: Durante as etapas de 'warmup' e 'skill', ou em sessões de mobilidade/prehab, INSCREVA OBRIGATORIAMENTE os "Exercícios Corretivos Recomendados" acima para corrigir os movimentos falhos.*

        [SESSÕES DE TREINO DISPONÍVEIS]
        ${formatTrainingSessions(ctx.trainingSessions || [])}

        [DIAS DE TREINO DESTA SEMANA]
${diasStr}

        [FORMATO COMPACTO - JSON PURO]
        {
          "exs": [
            {
              "dt": "YYYY-MM-DD", "dy": "Dia", "se": 1, "st": "tipo", "du": 60,
              "idx": 1, "ex": "nome", "et": "titulo", "eg": "grupo", "ey": "tipo_ex",
              "ts": 3, "de": "detalhes", "te": 0, "eu": "min", "re": 60, "ru": "seg",
              "tt": 0, "lo": "box", "sg": "workout", "al": ""
            }
          ]
        }
        
        [REGRAS CRÍTICAS DE ORDEM E FLUXO]
        1. Toda sessão deve seguir a ordem lógica: warmup -> skill -> strength -> workout -> cooldown.
        2. Nem toda sessão precisa de todos os estágios, mas os que existirem devem seguir a ordem acima.
        3. O campo 'idx' deve ser ÚNICO e CRESCENTE para toda a sessão (ex: warmup idx 1, skill idx 2, strength 3, workout idx 4).
        4. PREENCHA TODOS OS CAMPOS. Não retorne 0 ou null em re/ru/te/eu se a informação for relevante.
        5. Se ts > 1, o campo rest (re) DEVE ser > 0.
        6. Use APENAS as chaves curtas.
        7. O campo 'tt' (total_time) DEVE ser a soma estimada do bloco. NUNCA use 0 para exercícios ativos.
        8. LIMITE DE VOLUME: Aprox 6 exercícios por sessão principal e 4 por sessão de mobilidade/prep.
        9. TREINO INDIVIDUAL: Proibido prescrever 'Partner WODs' ou exercícios que dependam de outra pessoa.
        10. COERÊNCIA DE TEMPO: Reserve 2min de transição entre exercícios (não precisa colocar na tabela).
        11. Dias de treino:
${diasStr}
      `;

      console.log(`gerar_detalhamento: ${ctx.nome} semana ${ctx.semanaNum}/${ctx.totalSemanas} | coach: ${ai_coach_name ?? 'default'}`);

      const responseData = await generateWithProvider(prompt, provider, llmModel, genAI, `detalhamento_s${ctx.semanaNum}`, 16000);

      // Expansion: Maps short keys back to the long format expected by the App
      // And reinjects constant fields (week, mesocycle)
      const fullExercicios = await Promise.all((responseData.exs || []).map(async (short: any) => {
        // Fetches the closest link in the library
        const { data: link } = await supabaseClient.rpc('get_closest_exercise_link', { 
          search_name: short.et || short.ex 
        });

        const ts = Number(short.ts) || 1;
        const te = Number(short.te) || 0;
        const re = Number(short.re) || 0;
        const ai_tt = Number(short.tt) || 0;

        // Forced validation: always calculate the expected TT based on deterministic components
        const teMin = (short.eu === "seg") ? te / 60 : te;
        const reMin = (short.ru === "seg") ? re / 60 : re;
        const calc_tt = (teMin * ts) + (reMin * Math.max(0, ts - 1));

        // Decisive logic: if AI provided 0 or if there's a significant deviation (>0.1 min), 
        // we use the calculated value to ensure database integrity for KPIs.
        const tt_final = (ai_tt === 0 || Math.abs(ai_tt - calc_tt) > 0.1) 
                         ? Number(calc_tt.toFixed(1)) 
                         : ai_tt;

        return {
          date: short.dt || today, 
          week: Number(ctx.semanaNum) || 1,
          mesocycle: ctx.nome,
          day: short.dy || "",
          session: Number(short.se) || 1,
          session_type: short.st || "Metcon",
          duration: Number(short.du) || 60,
          workout_idx: Number(short.idx) || 1,
          exercise: short.ex || "Exercício não especificado",
          exercise_title: short.et || short.ex || "",
          exercise_group: short.eg || "Geral",
          exercise_type: short.ey || "Acessório",
          sets: ts,
          details: short.de || "",
          time_exercise: te,
          ex_unit: short.eu || "min",
          rest: re,
          rest_unit: short.ru || "seg",
          total_time: tt_final,
          location: short.lo || "Box",
          stage: short.sg || "workout",
          workout_link: link || "",
          adaptacaoLesao: short.al || ""
        };
      }));

      return new Response(JSON.stringify({ "exerciciosDetalhados": fullExercicios }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200
      });
    }

    // =========================================================
    // UNKNOWN ACTION
    // =========================================================
    else {
      return new Response(JSON.stringify({ error: `Ação desconhecida: ${acao}` }), { headers: corsHeaders, status: 400 })
    }

  } catch (error) {
    console.error("Erro Edge Function:", error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500
    });
  }
})
