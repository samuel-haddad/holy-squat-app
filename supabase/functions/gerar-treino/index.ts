import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI } from "npm:@google/generative-ai"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const allowedSessionTypes = "Acessório, Acessórios/Blindagem, Calistenia, Cardio, Cardio-Mobilidade, Core Strength, Core/Prep, Crossfit, Descanso, Endurance, Força/Heavy, Força/Metcon, Força/Skill, Full Body Pump, Full Session, Ginástica/Metcon, Hipertrofia/Blindagem, LPO, LPO/Força/Metcon, LPO/Metcon, LPO/Potência, Mobilidade, Mobilidade Flow, Mobilidade-Cardio, Mobilidade-Core, Mobilidade-Inferiores, Mobilidade/Prep, Multi, Musculação, Musculação-Cardio, Musculação-Funcional, Musculação/Força, Natação, Prehab/Força, Prehab/Mobilidade, Recuperação Ativa, Reintrodução/FBB, Skill, Skill/Metcon";

// =========================================================
// Helper: gera conteúdo com o provider correto (Google ou Anthropic)
// =========================================================
async function generateWithProvider(
  prompt: string,
  provider: string,
  llmModel: string,
  genAI: any,
  actionLabel: string,
  maxTokens: number = 16000
): Promise<any> {
  if (provider === 'google') {
    const model = genAI.getGenerativeModel(
      { model: llmModel, generationConfig: { responseMimeType: "application/json" } }
    );
    const result = await model.generateContent([prompt]);
    const usage = result.response.usageMetadata;
    console.log(`[TOKENS] ${actionLabel} | model: ${llmModel} | input: ${usage?.promptTokenCount ?? '?'} | output: ${usage?.candidatesTokenCount ?? '?'}`);
    return JSON.parse(result.response.text());

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
        system: "You are an AI CrossFit Coach. ALWAYS respond with PURE VALID JSON ONLY. No markdown, no pre-amble, no post-amble. Prohibited: Trailing commas in arrays/objects. Keys must be double-quoted.",
        messages: [{ role: 'user', content: prompt }],
      }),
    });
    const data = await response.json();
    if (!response.ok) {
      throw new Error(`Anthropic API error (${response.status}): ${JSON.stringify(data)}`);
    }

    const stopReason = data.stop_reason;
    console.log(`[TOKENS] ${actionLabel} | model: ${llmModel} | maxTok: ${maxTokens} | input: ${data.usage?.input_tokens} | output: ${data.usage?.output_tokens} | stop: ${stopReason}`);

    let rawText: string = data.content[0].text.trim();
    
    // 1. Markdown strip
    if (rawText.startsWith('```')) {
      rawText = rawText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();
    }

    // 2. Trailing comma fix (Claude Opus often leaves these at the end of large arrays)
    rawText = rawText.replace(/,\s*([\}\]])/g, '$1');

    try {
      return JSON.parse(rawText);
    } catch (e: any) {
      console.error(`[JSON ERROR] Falha ao parsear resposta do Claude em ${actionLabel}`);
      console.error(`[JSON PREVIEW] Primeiros 300: ${rawText.substring(0, 300)}`);
      console.error(`[JSON PREVIEW] Últimos 300: ${rawText.substring(rawText.length - 300)}`);
      throw new Error(`Invalid JSON from Claude at ${actionLabel}: ${e.message}`);
    }

  } else {
    throw new Error(`Provider desconhecido: ${provider}`);
  }
}

// =========================================================
// Helper: query na base de conhecimento (sempre Google Embeddings)
// =========================================================
async function queryKnowledgeBase(queryText: string, genAI: any, supabaseClient: any) {
  if (!queryText) return "";
  try {
    const embeddingModel = genAI.getGenerativeModel({ model: "text-embedding-004" });
    const result = await embeddingModel.embedContent(queryText);
    const embedding = result.embedding.values;
    const { data: documents, error } = await supabaseClient.rpc('match_knowledge_base', {
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
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const payload = await req.json()
    const {
      acao,
      email_utilizador,
      diretrizes_plano,
      plano_id,
      mesos_ja_gerados,
      actual_plan_summary_json,
      dias_semana,
      meso_context,
      ai_coach_name,  // NEW: nome do coach selecionado pelo usuário
    } = payload

    // ── Sempre instanciar genAI para embeddings (knowledge base) ──
    const genAI = new GoogleGenerativeAI(Deno.env.get('GEMINI_API_KEY')!)
    const today = new Date().toISOString().split('T')[0];

    // ── Buscar configuração do coach na tabela ai_coach ────────────
    let provider = 'google';
    let llmModel = 'gemini-pro-latest';

    if (ai_coach_name) {
      const { data: coachData, error: coachError } = await supabaseClient
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
    // AÇÃO: criar_plano_fase1
    // =========================================================
    if (acao === 'criar_plano_fase1') {
      const sixMonthsAgo = new Date();
      sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
      const dateStr = sixMonthsAgo.toISOString().split('T')[0];

      const [profileRes, prRes, benchRes, benchDefRes, workoutsRes, logsRes] = await Promise.all([
        supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single(),
        supabaseClient.from('pr_log').select('*').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks_logs').select('*').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks').select('*'),
        supabaseClient.from('workouts').select('date, exercise, exercise_title, sets, details').eq('user_email', email_utilizador).gte('date', dateStr).order('date', { ascending: false }).limit(150),
        supabaseClient.from('workouts_logs').select('workout_date, weight, reps_done, cardio_result, cardio_unit').eq('user_email', email_utilizador).gte('workout_date', dateStr).order('workout_date', { ascending: false }).limit(150)
      ]);

      const profile = profileRes.data || {};
      const knowledgeContext = await queryKnowledgeBase(diretrizes_plano?.objetivo || "", genAI, supabaseClient);

      const prompt = `
        Você é o AI Coach do Holy Squat App especialista em periodização de CrossFit.
        [DATA DE HOJE: ${today}]

        [PERFIL DO ATLETA]
        - Nome: ${profile.name}
        - Local: ${JSON.stringify(profile.where_train)}
        - Sessões/dia: ${profile.sessions_per_day} | Duração: ${profile.active_hours_value} ${profile.active_hours_unit}
        - About: ${profile.about_me || 'Não informado'}
        - Skills: ${profile.skills_training || 'Não informado'}
        - PRs: ${JSON.stringify(prRes.data || [])}
        - Benchmarks: ${JSON.stringify(benchRes.data || [])}
        - Histórico 6 meses: ${JSON.stringify(workoutsRes.data || [])}
        - Logs performance: ${JSON.stringify(logsRes.data || [])}

        [DIRETRIZES DO PLANO]
        - Objetivo: ${diretrizes_plano?.objetivo}
        - Início: ${diretrizes_plano?.data_inicio} | Fim: ${diretrizes_plano?.data_fim}
        - Competições: ${JSON.stringify(diretrizes_plano?.competicoes)}
        - Notas: ${diretrizes_plano?.notas}
        ${knowledgeContext}

        [MISSÃO — APENAS ESTRUTURA E CALENDÁRIO]
        Gere SOMENTE o planejamento estrutural. Os exercícios detalhados serão gerados por semana separadamente.

        1. analiseMacro: análise do histórico com gráficos.
        2. analiseMesocicloAnterior: { "aderencia": "", "evolucao": "", "texto": "", "graficos": [] }
        3. visaoGeralPlano:
           - blocos: TODOS os mesociclos com nome, duracaoSemanas, foco.
           - mesociclo1_consolidado: 1 linha por semana do Meso 1.
        4. visaoSemanal: TODOS os 7 dias de TODAS as semanas do Mesociclo 1.
           - isDescansoAtivo: true para dias de repouso.
           - week = intra-mesociclo (começa em 1).
           - ANO: ${today.split('-')[0]}.
        5. exerciciosDetalhados: [] (VAZIO)

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "analiseMacro": { "analise": "string", "historico": { "texto": "string", "graficos": [{ "tipo": "linha", "titulo": "string", "dados": [{ "x": "string", "y": 0 }] }] } },
          "analiseMesocicloAnterior": { "aderencia": "", "evolucao": "", "texto": "", "graficos": [] },
          "visaoGeralPlano": {
            "objetivoPrincipal": "string", "duracaoSemanas": 0,
            "fases": [{ "nome": "string", "duracao": "string", "foco": "string" }],
            "blocos": [{ "mesociclo": "string", "duracaoSemanas": 0, "foco": "string" }],
            "mesociclo1_consolidado": [{ "semana": 1, "foco": "string", "seg": "string", "ter": "string", "qua": "string", "qui": "string", "sex": "string", "sab": "string", "dom": "string" }]
          },
          "visaoSemanal": [{ "date": "YYYY-MM-DD", "day": "Segunda-feira", "session_type": "string", "focoPrincipal": "string", "isDescansoAtivo": false, "mesocycle": "string", "week": 1 }],
          "exerciciosDetalhados": []
        }
      `;

      console.log(`criar_plano_fase1 | coach: ${ai_coach_name ?? 'default'}`);
      const planData = await generateWithProvider(prompt, provider, llmModel, genAI, 'criar_plano_fase1', 16000);
      return new Response(JSON.stringify(planData), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 })
    }

    // =========================================================
    // AÇÃO: gerar_exercicios_semana
    // =========================================================
    else if (acao === 'gerar_exercicios_semana') {
      const ctx = meso_context || {};
      const diasStr = (dias_semana || [])
        .map((d: any) => `  - ${d.date} (${d.day}) | ${d.session_type} | ${d.focoPrincipal} | semana ${d.week}`)
        .join('\n');

      const prompt = `
        Você é o AI Coach do Holy Squat App. Gere os exercícios para a Semana ${ctx.semanaNum} de ${ctx.totalSemanas} do mesociclo "${ctx.nome}".
        [DATA DE HOJE: ${today}]

        [CONTEXTO]
        - Objetivo: ${ctx.objetivo}
        - Mesociclo: ${ctx.nome} | Semana ${ctx.semanaNum}/${ctx.totalSemanas}
        - Foco: ${ctx.focoSemana || 'Conforme planejamento'}
        - Local: ${JSON.stringify(ctx.whereTrain)}
        - Sessões/dia: ${ctx.sessionsPerDay || 1}

        [DIAS DE TREINO DESTA SEMANA]
${diasStr}

        [MISSÃO]
        Gere exercícios COMPLETOS para cada dia de treino listado.
        - workout_idx: índice sequencial por sessão (começa em 1).
        - week = ${ctx.semanaNum} (intra-mesociclo).
        - mesocycle = "${ctx.nome}".
        - session_type (use apenas): [${allowedSessionTypes}]
        - ANO: ${today.split('-')[0]}.

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "exerciciosDetalhados": [
            {
              "date": "YYYY-MM-DD", "week": ${ctx.semanaNum}, "mesocycle": "${ctx.nome}",
              "day": "string", "session": 1, "session_type": "string", "duration": 60,
              "workout_idx": 1, "exercise": "string", "exercise_title": "string",
              "exercise_group": "string", "exercise_type": "string", "sets": 0,
              "details": "string", "time_exercise": 0, "ex_unit": "min",
              "rest": 0, "rest_unit": "seg", "rest_round": 0, "rest_round_unit": "min",
              "total_time": 0, "location": "string", "stage": "workout", "adaptacaoLesao": ""
            }
          ]
        }
      `;

      console.log(`gerar_exercicios_semana: ${ctx.nome} semana ${ctx.semanaNum}/${ctx.totalSemanas} | coach: ${ai_coach_name ?? 'default'}`);
      
      // Prompt otimizado para economia extrema de tokens (chaves curtas)
      const compactPrompt = `
        Você é o AI Coach. Gere os exercícios para a Semana ${ctx.semanaNum} do meso "${ctx.nome}".
        [FORMATO COMPACTO - JSON PURO]
        {
          "exs": [
            {
              "dt": "YYYY-MM-DD", "dy": "Dia", "se": 1, "st": "tipo", "du": 60,
              "idx": 1, "ex": "nome", "et": "titulo", "eg": "grupo", "ey": "tipo_ex",
              "ts": 3, "de": "detalhes", "te": 0, "eu": "min", "re": 60, "ru": "seg",
              "rr": 0, "rru": "min", "tt": 0, "lo": "box", "sg": "workout", "al": ""
            }
          ]
        }
        
        [REGRAS]
        - Use APENAS as chaves curtas acima.
        - Seja conciso em "de" (detalhes).
        - Dias de treino:
${diasStr}
      `;

      const responseData = await generateWithProvider(compactPrompt, provider, llmModel, genAI, `semana_${ctx.semanaNum}`, 16000);
      
      // Expansão: Mapeia as chaves curtas de volta para o formato longo esperado pelo App
      // E reinjeta os campos constantes (week, mesocycle)
      const fullExercicios = (responseData.exs || []).map((short: any) => ({
        date: short.dt,
        week: ctx.semanaNum,
        mesocycle: ctx.nome,
        day: short.dy,
        session: short.se,
        session_type: short.st,
        duration: short.du,
        workout_idx: short.idx,
        exercise: short.ex,
        exercise_title: short.et,
        exercise_group: short.eg,
        exercise_type: short.ey,
        sets: short.ts,
        details: short.de,
        time_exercise: short.te,
        ex_unit: short.eu,
        rest: short.re,
        rest_unit: short.ru,
        rest_round: short.rr,
        rest_round_unit: short.rru,
        total_time: short.tt,
        location: short.lo,
        stage: short.sg,
        adaptacaoLesao: short.al
      }));

      return new Response(JSON.stringify({ "exerciciosDetalhados": fullExercicios }), { 
        headers: { ...corsHeaders, "Content-Type": "application/json" }, 
        status: 200 
      });
    }

    // =========================================================
    // AÇÃO: gerar_proximo_meso_fase1
    // =========================================================
    else if (acao === 'gerar_proximo_meso_fase1') {
      const planRes = await supabaseClient.from('training_plans').select('*').eq('id', plano_id || '').single();
      const planData = planRes.data || {};
      const startDate = planData.start_date;

      const twelveMonthsBefore = new Date(startDate);
      twelveMonthsBefore.setFullYear(twelveMonthsBefore.getFullYear() - 1);
      const preMacroDateStr = twelveMonthsBefore.toISOString().split('T')[0];

      const [prRes, benchRes, benchDefRes, postWorkoutsRes, postLogsRes, profileRes] = await Promise.all([
        supabaseClient.from('pr_log').select('exercise, value, unit, date').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks_logs').select('*').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks').select('*'),
        supabaseClient.from('workouts').select('date, exercise, exercise_title, sets').eq('user_email', email_utilizador).gte('date', startDate).lte('date', today).order('date', { ascending: false }).limit(80),
        supabaseClient.from('workouts_logs').select('workout_date, weight, reps_done, pse').eq('user_email', email_utilizador).gte('workout_date', startDate).lte('workout_date', today).order('workout_date', { ascending: false }).limit(80),
        supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single()
      ]);

      let planSummary: any = {};
      try {
        planSummary = actual_plan_summary_json
          ? JSON.parse(actual_plan_summary_json)
          : (planData.actual_plan_summary ? JSON.parse(planData.actual_plan_summary) : {});
      } catch (e) { console.error("parse plan summary error:", e); }

      const todosOsMesos: any[] = planSummary.blocos || [];
      const mesosJaGeradosArr: string[] = mesos_ja_gerados || [];
      const proximoMeso = todosOsMesos.find((b: any) => !mesosJaGeradosArr.includes(b.mesociclo));
      const duracaoProximoMeso = proximoMeso?.duracaoSemanas || 4;
      const nomeProximoMeso = proximoMeso?.mesociclo || 'Próximo Meso';
      const profile = profileRes.data || {};

      const prompt = `
        Você é o AI Coach do Holy Squat App gerando o PRÓXIMO MESOCICLO.
        [DATA DE HOJE: ${today}]

        [PLANO MACRO]
        - Período: ${planData.start_date} a ${planData.end_date}
        - Todos os mesos: ${JSON.stringify(todosOsMesos)}
        - Já gerados: ${mesosJaGeradosArr.join(', ') || 'Nenhum'}
        - PRÓXIMO: "${nomeProximoMeso}" — ${duracaoProximoMeso} semanas | ${proximoMeso?.foco || ''}

        [ATLETA]
        - Nome: ${profile.name} | Local: ${JSON.stringify(profile.where_train)}
        - Sessões/dia: ${profile.sessions_per_day}
        - PRs: ${JSON.stringify(prRes.data || [])}
        - Progresso no macro: ${JSON.stringify(postWorkoutsRes.data || [])}
        - Logs PSE: ${JSON.stringify(postLogsRes.data || [])}

        [MISSÃO — ESTRUTURA + CALENDÁRIO (sem exercícios)]
        Retorne JSON com analiseMacro, analiseMesocicloAnterior, visaoGeralPlano,
        visaoSemanal (7 dias × ${duracaoProximoMeso} semanas), exerciciosDetalhados: [].
        - week = intra-mesociclo (começa em 1).
        - mesocycle = "${nomeProximoMeso}".
        - ANO: ${today.split('-')[0]}.

        [FORMATO — JSON PURO]
        {
          "analiseMacro": { "analise": "string", "historico": { "texto": "string", "graficos": [] } },
          "analiseMesocicloAnterior": { "aderencia": "string", "evolucao": "string", "texto": "string", "graficos": [] },
          "visaoGeralPlano": { "objetivoPrincipal": "string", "duracaoSemanas": 0, "fases": [], "blocos": [], "mesociclo1_consolidado": [] },
          "visaoSemanal": [{ "date": "YYYY-MM-DD", "day": "string", "session_type": "string", "focoPrincipal": "string", "isDescansoAtivo": false, "mesocycle": "${nomeProximoMeso}", "week": 1 }],
          "exerciciosDetalhados": [],
          "_mesoContext": { "nome": "${nomeProximoMeso}", "semanas": ${duracaoProximoMeso}, "startDate": "${planData.start_date}", "endDate": "${planData.end_date}", "sessionsPerDay": ${profile.sessions_per_day || 1}, "whereTrain": ${JSON.stringify(profile.where_train || [])} }
        }
      `;

      console.log(`gerar_proximo_meso_fase1 | coach: ${ai_coach_name ?? 'default'}`);
      const fase1Data = await generateWithProvider(prompt, provider, llmModel, genAI, 'proximo_meso_fase1', 16000);
      return new Response(JSON.stringify(fase1Data), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 })
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
