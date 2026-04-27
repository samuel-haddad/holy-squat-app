import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI } from "npm:@google/generative-ai"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const COACH_PERSONA = `Você é o AI Coach do Holy Squat App. Seu perfil: Coach Level de Crossfit, com grande conhecimento sobre reabilitação de lesões, em especial de ombro e joelho, especializado na integração do treinamento de força tradicional, com ênfase em isolamento, bodybuilding funcional e protocolos de Prehab para CrossFit. Seu foco são protocolos de Concurrent Training que buscam mitigar o "efeito de interferência" entre eles.`;

const METRICS_DEFINITIONS = `
[DICIONÁRIO E INTERPRETAÇÃO DE MÉTRICAS (KPIs)]
1. Adherence (Taxa de Adesão): % de exercícios planejados concluídos nos últimos 180 dias (Ignorando sessões de Descanso). 
   - Interpretação: > 90% (Alta disciplina); < 70% (Necessário reduzir volume ou ajustar rotina).
2. IFR (Índice de Força Relativa): Soma dos melhores PRs em Back Squat, Deadlift e Press dividida pelo peso corporal, considerando os melhores resultados dos últimos 6 meses.
   - Interpretação: Exprime a força bruta em relação ao peso do atleta. > 5.0 (Excelente); 3.0-4.0 (Intermediário).
3. Avg_PSE (Média de Esforço Percebido): Média da escala 1-10 nos últimos 180 dias de treino.
   - Interpretação: 8-9 (Limite/Risco de burnout); 5-6 (Manutenção/Base aeróbica).
4. Best_Evolution: Comparação % entre Esforço Global atual (último mês) e baseline de 6 meses.
   - Interpretação: Positivo (Overload progressivo); Negativo (Deload ou perda de consistência).
5. Weekly_Freq: Média de dias únicos treinados por semana nos últimos 180 dias (Soma de dias treinados / 26 semanas).
   - Interpretação: Mede o ritmo biológico e a capacidade de recuperação (recovery).
6. Streak: Semanas consecutivas com pelo menos 3 treinos realizados.
   - Interpretação: Mede resiliência e formação de hábito. Mais valioso que o streak diário.
`;

// Helper: format training sessions for LLM
function formatTrainingSessions(sessions: any[]): string {
  if (!sessions || sessions.length === 0) {
    throw new Error("Nenhuma sessão de treino configurada. Por favor, configure suas sessões no perfil ou no onboarding antes de prosseguir.");
  }
  return sessions.map((s: any) => 
    `- Sessão ${s.session_number}: Locais=[${s.locations?.join(', ')}] | Duração=${s.duration_minutes}min | Dias=[${s.schedule?.join(', ')}] | Turno=${s.time_of_day}${s.notes ? ` | Notas: ${s.notes}` : ''}`
  ).join('\n        ');
}

// Helper: format the structured history summary for the LLM
function formatHistorySummary(summary: any): string {
  if (!summary) return "Sem histórico disponível.";
  const lines: string[] = [];

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

  if (summary.top_exercises?.length) {
    lines.push('[TOP 15 EXERCÍCIOS — FREQUÊNCIA (todos os estágios menos warm/cool)]');
    for (const ex of summary.top_exercises) {
      lines.push(`${ex.exercise} (${ex.group} | ${ex.type}): ${ex.freq}x | Último: ${ex.last}`);
    }
    lines.push('');
  }

  if (summary.quarterly_progression?.length) {
    lines.push('[PROGRESSÃO TRIMESTRAL — LEVANTAMENTOS-CHAVE]');
    for (const ex of summary.quarterly_progression) {
      const qStr = (ex.quarters || []).map((q: any) => `${q.q}: avg ${q.avg}kg / max ${q.max}kg`).join(' → ');
      lines.push(`${ex.exercise}: ${qStr}`);
    }
  }

  return lines.join('\n');
}

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
  const targetTemperature = provider === 'anthropic' ? 0.2 : 0.7;
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
        const anthropicBody: any = {
          model: llmModel,
          max_tokens: maxTokens,
          system: "You are an AI CrossFit Coach. ALWAYS respond with PURE VALID JSON ONLY. No markdown, no pre-amble, no post-amble. Prohibited: Trailing commas in arrays/objects. Keys must be double-quoted.",
          messages: [{ role: 'user', content: prompt }],
        };
        
        // Remove temperature for Anthropic as it's deprecated for some models
        // if (targetTemperature !== undefined) anthropicBody.temperature = targetTemperature;

        const response = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': Deno.env.get('ANTHROPIC_API_KEY') ?? '',
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify(anthropicBody),
        });
        
        const data = await response.json();
        if (!response.ok) {
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
        const delay = attempt * 3500;
        console.warn(`[RETRY] Rate limit (429) detectado em ${actionLabel}. Tentativa ${attempt}/${maxRetries}. Aguardando ${delay}ms...`);
        await sleep(delay);
        continue;
      }
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

// Helper: query the knowledge base
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
    const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() || '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim() || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() || '';
    const geminiKey = Deno.env.get('GEMINI_API_KEY')?.trim() || '';

    if (!supabaseServiceKey) console.warn("[WARN] SUPABASE_SERVICE_ROLE_KEY não encontrada no ambiente.");

    const adminClient = createClient(
      supabaseUrl,
      supabaseServiceKey || supabaseAnonKey
    )

    const payload = await req.json()
    const { acao, ai_coach_name } = payload

    if (!geminiKey) throw new Error("GEMINI_API_KEY não configurada nas secrets do Supabase.");
    const genAI = new GoogleGenerativeAI(geminiKey)
    const today = new Date().toISOString().split('T')[0];

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
    // =========================================================
    if (acao === 'gerar_analise_historica') {
      const { email_utilizador, user_id } = payload;
      if (!email_utilizador && !user_id) throw new Error("Parâmetros email_utilizador ou user_id ausentes.");
      console.log(`[Action 1] Iniciando para ${email_utilizador || user_id}`);

      const profileQuery = user_id 
        ? adminClient.from('profiles').select('*').eq('id', user_id).single()
        : adminClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const [profileRes, prRes] = await Promise.all([
        profileQuery,
        adminClient.from('pr_log')
          .select('exercise, pr, pr_unit, date')
          .eq('user_email', email_utilizador)
          .order('date', { ascending: false })
          .limit(100)
      ]);

      const profile = profileRes.data || {};
      const rawWeight = Number(profile.weight) || 0;
      const weightUnitRaw = (profile.weight_unit || '').toLowerCase().trim();
      const isLbs = weightUnitRaw.includes('lb');
      // Garante que p_user_weight está sempre em kg, independente da unidade do perfil
      const userWeight = isLbs ? rawWeight * 0.453592 : rawWeight;

      const athleteStatsRes = await adminClient.rpc('get_athlete_planning_stats', { 
        p_email: email_utilizador,
        p_user_weight: userWeight
      });

      const statsRaw = athleteStatsRes?.data;
      const statsObj = Array.isArray(statsRaw) ? statsRaw[0] : statsRaw;
      const athleteStats = payload.athlete_stats_summary || (statsObj?.kpis) || {};

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



      const { data: historySummaryRaw } = await adminClient
        .rpc('get_athlete_history_summary', { p_email: email_utilizador });

      const rpcPayload = Array.isArray(historySummaryRaw) ? historySummaryRaw[0] : historySummaryRaw;
      let historySummaryText = formatHistorySummary(rpcPayload);
      const rpcProducedContent = historySummaryText.length > 60;

      if (!rpcProducedContent) {
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
        const wodMap: Record<string, any> = {};
        for (const w of rawWorkouts) wodMap[w.wod_exercise_id] = w;

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
      }

      const effectiveIfr = athleteStats.ifr || 0;



      let techniqueFeedbacksStr = "Nenhum feedback de técnica registrado.";
      if (profile?.id) {
        const { data: tfData } = await adminClient
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

      console.time('[perf] rag_query');
      const ragQuery = `${profile.anamnesis || ''} ${profile.training_goal || ''}`;
      const knowledgeContext = await queryKnowledgeBase(ragQuery, genAI, adminClient);
      console.timeEnd('[perf] rag_query');

      const prompt = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]
        ${payload.model_observations ? `\n        [OBSERVAÇÕES DO MODELO]\n        ${payload.model_observations}\n` : ''}
        [MISSÃO — ANÁLISE DO HISTÓRICO ESPORTIVO]
        Analise detalhadamente o histórico do atleta abaixo. Não se limite a resumir logs; você deve 
        interpretar a trajetória do atleta. 
        
        [HIERARQUIA DE ANÁLISE - PRIORIDADE DE DADOS]
        1. MARCAS ABSOLUTAS: PRs e Benchmarks são as suas "âncoras de verdade". Use-os para validar se os treinos recentes estão de acordo com a capacidade real do atleta.
        2. MÉTRICAS DERIVADAS: Utilize o IFR (baseado no histórico de treinos do período analisado) para avaliar a força relativa por KG.
        3. TENDÊNCIA DE CARGA: Observe se a 'Evolution' e 'Workload' corroboram os recordes ou se há um platô.

        [CONTEXTO CIENTÍFICO (RAG)]
        ${knowledgeContext}

        [DICIONÁRIO DE MÉTRICAS]
        ${METRICS_DEFINITIONS}

        [KPIs DETERMINÍSTICOS DO ATLETA]
        - Aderência Global: ${athleteStats.adherence}%
        - PSE Médio (90 dias): ${athleteStats.avg_pse}
        - IFR (Índice de Força Relativa): ${effectiveIfr} (calculado a partir dos melhores resultados nos treinos do período analisado)
        - Evolução de Esforço: ${athleteStats.best_evolution?.percent}% vs baseline 6 meses
        - Streak Atual: ${athleteStats.streak} semanas
        - Frequência Semanal: ${athleteStats.weekly_freq} treinos/semana

        [PERFIL DO ATLETA]
        - Nome: ${profile.name}
        - Peso Corporal: ${userWeight} kg
        - Anamnese: ${profile.anamnesis || 'Não informado'}
        - Objetivo: ${profile.training_goal || 'Não informado'}
        - Esporte Favorito: ${profile.favorite_sport || 'Não informado'}

        [AVALIAÇÃO BIOMECÂNICA E TÉCNICA (TECHNIQUE FEEDBACK)]
        O atleta realizou testes de biomecânica usando IA. Aqui estão os feedbacks mais recentes:
        ${techniqueFeedbacksStr}
        *DIRETRIZ: Mencione essas deficiências na sua análise e recomende a correção rigorosa nas etapas de Skill e Prehab.*

        [PRs DE FORÇA — MELHOR MARCA POR EXERCÍCIO]
        ${prMaxPerExercise.length > 0
          ? prMaxPerExercise.map((r: any) => `- ${r.exercise}: ${r.pr} ${r.pr_unit || 'kg'} (${r.date})`).join('\n        ')
          : 'Nenhum PR registrado.'}

        [HISTÓRICO AGREGADO — 12 MESES]
        ${historySummaryText || 'Nenhum dado de treino encontrado nos últimos 6 meses.'}

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "analiseMacro": {
            "analise": "string",
            "historico": {
              "texto": "string"
            }
          }
        }
      `;

      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'gerar_analise_historica', 8000);
      const statsData = athleteStatsRes?.data;
      const hasValidStats = statsData && statsData.kpis && statsData.radar !== undefined;
      const responseBody = { ...result, athlete_stats_snapshot: hasValidStats ? statsData : null };
      return new Response(JSON.stringify(responseBody), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    // =========================================================
    // ACTION 2: criar_plano
    // =========================================================
    else if (acao === 'criar_plano') {
      const { email_utilizador, user_id, analise_historica, diretrizes_plano, training_sessions } = payload;
      const profileQuery = user_id 
        ? adminClient.from('profiles').select('*').eq('id', user_id).single()
        : adminClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const { data: profileDb } = await profileQuery;
      const profile = profileDb || {};
      const analise = analise_historica || {};
      const sessions = training_sessions || [];

      const prompt = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]

        [MISSÃO — PROJETAR BLOCOS DO MACROCICLO]
        Projética um macrociclo completo dividido em mesociclos. Define nome, duração em semanas e foco de cada bloco.

        [HIERARQUIA DE PRIORIDADE - LEI ZERO]
        1. COMPETIÇÕES: Respeite rigorosamente as datas de início e fim das competições.
        2. NOMENCLATURA: Use apenas os session_type da lista oficial.

        [ANÁLISE DO HISTÓRICO]
        ${JSON.stringify(analise)}

        [PERFIL DO ATLETA]
        - Nome: ${profile.name}
        - Anamnese: ${profile.anamnesis || 'Não informado'}

        [SESSÕES DE TREINO DISPONÍVEIS]
        ${formatTrainingSessions(sessions)}

        [DIRETRIZES DO PLANO]
        - Objetivo: ${diretrizes_plano?.objetivo}
        - Início: ${diretrizes_plano?.data_inicio} | Fim: ${diretrizes_plano?.data_fim}
        - Competições: ${JSON.stringify(diretrizes_plano?.competicoes)}
        - Férias: ${JSON.stringify(diretrizes_plano?.ferias)}
        - Lesões: ${JSON.stringify(diretrizes_plano?.lesoes)}

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "visaoGeralPlano": {
            "objetivoPrincipal": "string",
            "duracaoSemanas": 0,
            "fases": [{ "nome": "string", "duracao": "string", "foco": "string" }],
            "blocos": [
              { "mesociclo": "string", "duracaoSemanas": 4, "foco": "string" }
            ]
          }
        }
      `;

      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'criar_plano', 8000);
      return new Response(JSON.stringify(result), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

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
