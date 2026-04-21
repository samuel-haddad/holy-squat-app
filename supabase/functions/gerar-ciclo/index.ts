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

// Helper: format training sessions for LLM
function formatTrainingSessions(sessions: any[]): string {
  if (!sessions || sessions.length === 0) {
    throw new Error("Nenhuma sessão de treino configurada. Por favor, configure suas sessões no perfil ou no onboarding antes de prosseguir.");
  }
  return sessions.map((s: any) => 
    `- Sessão ${s.session_number}: Locais=[${s.locations?.join(', ')}] | Duração=${s.duration_minutes}min | Dias=[${s.schedule?.join(', ')}] | Turno=${s.time_of_day}${s.notes ? ` | Notas: ${s.notes}` : ''}`
  ).join('\n        ');
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
        let rawText = result.response.text();
        if (rawText.startsWith('```')) {
          rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
        }
        return JSON.parse(rawText);

      } else if (provider === 'anthropic') {
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
          if (response.status === 429) throw new Error(`429: ${JSON.stringify(data)}`);
          throw new Error(`Anthropic API error (${response.status}): ${JSON.stringify(data)}`);
        }

        let rawText: string = data.content[0].text.trim();
        if (rawText.startsWith('```')) {
          rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
        }
        rawText = rawText.replace(/,\s*([\}\]])/g, '$1');

        try {
          return JSON.parse(rawText);
        } catch (e: any) {
          throw new Error(`Invalid JSON from Claude at ${actionLabel}: ${e.message}`);
        }

      } else {
        throw new Error(`Provider desconhecido: ${provider}`);
      }

    } catch (err: any) {
      const errorText = err.message || '';
      const isRateLimit = errorText.includes('429') || errorText.toLowerCase().includes('quota') || errorText.toLowerCase().includes('limit');
      
      if (isRateLimit && attempt < maxRetries) {
        await sleep(attempt * 3500);
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

async function queryKnowledgeBase(queryText: string, genAI: any, adminClient: any) {
  if (!queryText) return "";
  try {
    const embedding = await getEmbedding(queryText);
    const { data: documents, error } = await adminClient.rpc('match_knowledge_base', {
      query_embedding: embedding,
      match_threshold: 0.4,
      match_count: 5
    });
    if (error) return "";
    if (documents && documents.length > 0) {
      return `\n[LITERATURA CIENTÍFICA]\n${documents.map((d: any) => d.content).join("\n---\n")}\n`;
    }
    return "";
  } catch (err) {
    return "";
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() || '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim() || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() || '';
    const geminiKey = Deno.env.get('GEMINI_API_KEY')?.trim() || '';

    if (!supabaseServiceKey) console.warn("[WARN] SUPABASE_SERVICE_ROLE_KEY não encontrada no ambiente.");

    const supabaseClient = createClient(
      supabaseUrl,
      supabaseAnonKey,
      { global: { headers: { Authorization: req.headers.get('Authorization') || `Bearer ${supabaseAnonKey}` } } }
    )

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
      const { data: coachData } = await adminClient
        .from('ai_coach')
        .select('llm_model, provider')
        .eq('ai_coach_name', ai_coach_name)
        .single();
      if (coachData) {
        provider = coachData.provider;
        llmModel = coachData.llm_model;
      }
    }

    // =========================================================
    // ACTION 3: gerar_proximo_ciclo
    // =========================================================
    if (acao === 'gerar_proximo_ciclo') {
      const { email_utilizador, user_id, bloco_atual, performance_stats, cycle_snapshot, training_sessions, data_inicio_meso, contexto_macrociclo } = payload;
      const profileRes = user_id 
        ? await supabaseClient.from('profiles').select('*').eq('id', user_id).single()
        : await supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const profile = profileRes.data || {};
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

        [CONTEXTO DO MACROCICLO]
        - Análise Histórica: ${JSON.stringify(macroCtx.analise_historica || 'Não fornecida')}
        - Visão Geral do Plano: ${JSON.stringify(macroCtx.visao_geral_plano || 'Não fornecida')}
        - COMPETIÇÕES: ${JSON.stringify(macroCtx.competicoes || [])}

        [SESSÕES CONFIGURADAS]
        ${formatTrainingSessions(sessions)}
        
        [BLOCO ATUAL DO MESOCICLO]
        - Nome: ${bloco.mesociclo} | Foco: ${bloco.foco}

        [ATLETA]
        - Nome: ${profile.name}

        [TECNICA]
        ${techniqueFeedbacksStr}

        [KPIs CICLO ANTERIOR]
        ${JSON.stringify(perfStats)}

        [SNAPSHOT ATLETA]
        ${JSON.stringify(cycleSnap?.kpis || {})}

        [FORMATO — JSON]
        {
          "analiseCicloAnterior": { "aderencia": "string", "evolucao": "string", "texto": "string" },
          "visaoGeralCiclo": [{ "semana": 1, "foco": "string", "seg": "string", "ter": "string", "qua": "string", "qui": "string", "sex": "string", "sab": "string", "dom": "string" }],
          "visaoSemanal": [{ "date": "YYYY-MM-DD", "session": 1, "session_type": "string", "focoPrincipal": "string", "isDescansoAtivo": false }]
        }
      `;

      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'gerar_proximo_ciclo', 8000);

      if (result.visaoSemanal && Array.isArray(result.visaoSemanal)) {
        const diasSemana = ["Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado"];
        result.visaoSemanal = result.visaoSemanal.map((dia: any) => {
          const d = new Date(dia.date + 'T12:00:00Z');
          const dayName = diasSemana[d.getUTCDay()];
          let weekNum = 1;
          if (data_inicio_meso) {
            const startD = new Date(data_inicio_meso + 'T12:00:00Z');
            const diffMs = d.getTime() - startD.getTime();
            if (diffMs > 0) weekNum = Math.floor(diffMs / (7 * 24 * 60 * 60 * 1000)) + 1;
          }
          return { ...dia, day: dayName, mesocycle: bloco.mesociclo, week: weekNum };
        });
      }
      return new Response(JSON.stringify(result), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    // =========================================================
    // ACTION 4: gerar_detalhamento
    // =========================================================
    else if (acao === 'gerar_detalhamento') {
      const { email_utilizador, user_id, visao_semanal, meso_context } = payload;
      const ctx = meso_context || {};
      
      let techniqueFeedbacksStr = "Nenhum feedback de técnica registrado.";
      const profileRes = user_id 
        ? await adminClient.from('profiles').select('id').eq('id', user_id).single()
        : await adminClient.from('profiles').select('id').eq('email', email_utilizador).single();

      if (profileRes.data?.id) {
        const { data: tfData } = await adminClient
          .from('technique_feedbacks')
          .select('exercise_name, resume_text, improve_exercises')
          .eq('user_id', profileRes.data.id)
          .order('created_at', { ascending: false })
          .limit(15);
        if (tfData && tfData.length > 0) {
          techniqueFeedbacksStr = tfData.map((tf: any) => 
            `- Exercício Original: ${tf.exercise_name}\n  Problema/Resumo: ${tf.resume_text}\n  Exercícios Corretivos Recomendados: ${JSON.stringify(tf.improve_exercises)}`
          ).join('\n');
        }
      }

      const diasStr = (visao_semanal || []).map((d: any) => `  - ${d.date} (${d.day}) | session ${d.session || 1} | ${d.session_type} | ${d.focoPrincipal}`).join('\n');

      const ragQuery = `${ctx.focoSemana || ''} ${ctx.objetivo || ''} exercícios crossfit`;
      const knowledgeContext = await queryKnowledgeBase(ragQuery, genAI, adminClient);

      const prompt = `
        ${COACH_PERSONA} Gere os exercícios para a Semana ${ctx.semanaNum} de ${ctx.totalSemanas} do mesociclo "${ctx.nome}".
        [DATA DE HOJE: ${today}]
        [CONTEXTO CIENTÍFICO (RAG)]
        ${knowledgeContext}
        ${DATA_CONTRACT}
        ${FEW_SHOT_EXAMPLES}
        [TECNICA]
        ${techniqueFeedbacksStr}
        [SESSÕES CONFIGURADAS]
        ${formatTrainingSessions(ctx.trainingSessions || [])}
        [DIAS]
${diasStr}
        [FORMATO — JSON COMPACTO]
        { "exs": [{ "dt": "YYYY-MM-DD", "dy": "Dia", "se": 1, "st": "tipo", "du": 60, "idx": 1, "ex": "nome", "et": "titulo", "eg": "grupo", "ey": "tipo_ex", "ts": 3, "de": "detalhes", "te": 0, "eu": "min", "re": 60, "ru": "seg", "tt": 0, "lo": "box", "sg": "workout", "al": "" }] }
      `;

      const responseData = await generateWithProvider(prompt, provider, llmModel, genAI, `detalhamento_s${ctx.semanaNum}`, 16000);

      const fullExercicios = await Promise.all((responseData.exs || []).map(async (short: any) => {
        const { data: link } = await adminClient.rpc('get_closest_exercise_link', { search_name: short.et || short.ex });
        const ts = Number(short.ts) || 1;
        const te = Number(short.te) || 0;
        const re = Number(short.re) || 0;
        const ai_tt = Number(short.tt) || 0;
        const teMin = (short.eu === "seg") ? te / 60 : te;
        const reMin = (short.ru === "seg") ? re / 60 : re;
        const calc_tt = (teMin * ts) + (reMin * Math.max(0, ts - 1));
        const tt_final = (ai_tt === 0 || Math.abs(ai_tt - calc_tt) > 0.1) ? Number(calc_tt.toFixed(1)) : ai_tt;

        return {
          date: short.dt || today, week: Number(ctx.semanaNum) || 1, mesocycle: ctx.nome, day: short.dy || "", session: Number(short.se) || 1, session_type: short.st || "Metcon", duration: Number(short.du) || 60, workout_idx: Number(short.idx) || 1, exercise: short.ex || "Exercício não especificado", exercise_title: short.et || short.ex || "", exercise_group: short.eg || "Geral", exercise_type: short.ey || "Acessório", sets: ts, details: short.de || "", time_exercise: te, ex_unit: short.eu || "min", rest: re, rest_unit: short.ru || "seg", total_time: tt_final, location: short.lo || "Box", stage: short.sg || "workout", workout_link: link || "", adaptacaoLesao: short.al || ""
        };
      }));

      return new Response(JSON.stringify({ "exerciciosDetalhados": fullExercicios }), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    else return new Response(JSON.stringify({ error: `Ação desconhecida: ${acao}` }), { headers: corsHeaders, status: 400 })

  } catch (error) {
    console.error("Erro Edge Function:", error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 });
  }
})
