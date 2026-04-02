import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI } from "npm:@google/generative-ai"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const allowedSessionTypes = "Acessório, Acessórios/Blindagem, Calistenia, Cardio, Cardio-Mobilidade, Core Strength, Core/Prep, Crossfit, Descanso, Endurance, Força/Heavy, Força/Metcon, Força/Skill, Full Body Pump, Full Session, Ginástica/Metcon, Hipertrofia/Blindagem, LPO, LPO/Força/Metcon, LPO/Metcon, LPO/Potência, Mobilidade, Mobilidade Flow, Mobilidade-Cardio, Mobilidade-Core, Mobilidade-Inferiores, Mobilidade/Prep, Multi, Musculação, Musculação-Cardio, Musculação-Funcional, Musculação/Força, Natação, Prehab/Força, Prehab/Mobilidade, Recuperação Ativa, Reintrodução/FBB, Skill, Skill/Metcon";

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
      // gerar_exercicios_semana params:
      dias_semana,       // List of training days for ONE week (non-rest days only)
      meso_context,      // { nome, objetivo, dataInicio, dataFim, semanaNum, totalSemanas, sessionsPerDay, whereTrain }
    } = payload

    const genAI = new GoogleGenerativeAI(Deno.env.get('GEMINI_API_KEY')!)
    const today = new Date().toISOString().split('T')[0];
    const model = genAI.getGenerativeModel(
      { model: "gemini-pro-latest", generationConfig: { responseMimeType: "application/json" } }
    )

    // =========================================================
    // AÇÃO: criar_plano_fase1
    // 1 chamada Gemini — retorna estrutura + visaoSemanal (sem exercícios)
    // Output pequeno: ~30-60K tokens → sem WORKER_LIMIT
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
        Gere SOMENTE o planejamento estrutural. Os exercícios detalhados serão gerados depois semana a semana.
        Retorne APENAS estes campos:

        1. analiseMacro: análise do histórico com gráficos (volume, PRs, frequência).
        2. analiseMesocicloAnterior: { "aderencia": "", "evolucao": "", "texto": "", "graficos": [] }
        3. visaoGeralPlano:
           - objetivoPrincipal, duracaoSemanas, fases
           - blocos: TODOS os mesociclos com nome, duracaoSemanas, foco.
           - mesociclo1_consolidado: 1 linha por semana do Meso 1 (seg/ter/qua/qui/sex/sab/dom = tipo de treino).
        4. visaoSemanal: TODOS os 7 dias de TODAS as semanas do Mesociclo 1.
           - 7 dias/semana sem exceção (Segunda a Domingo).
           - isDescansoAtivo: true para dias de repouso.
           - week = número intra-mesociclo (começa em 1).
           - ANO OBRIGATÓRIO: ${today.split('-')[0]}.
        5. exerciciosDetalhados: [] (VAZIO — será gerado por semana separadamente)

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

      console.log("criar_plano_fase1: gerando estrutura + visaoSemanal...");
      const result = await model.generateContent([prompt]);
      const usage = result.response.usageMetadata;
      console.log(`[TOKENS] criar_plano_fase1 | input: ${usage?.promptTokenCount ?? '?'} | output: ${usage?.candidatesTokenCount ?? '?'} | total: ${usage?.totalTokenCount ?? '?'}`);
      const planData = JSON.parse(result.response.text());
      return new Response(JSON.stringify(planData), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 })
    }

    // =========================================================
    // AÇÃO: gerar_exercicios_semana
    // 1 chamada Gemini — gera exercícios de UMA semana (~5 dias × ~8 exercícios)
    // Output pequeno: ~8-15K tokens → ZERO probabilidade de WORKER_LIMIT
    // Usada tanto em criar_plano quanto em gerar_proximo_meso
    // =========================================================
    else if (acao === 'gerar_exercicios_semana') {
      // dias_semana: array de { date, day, session_type, focoPrincipal, week, mesocycle }
      // meso_context: { nome, objetivo, dataInicio, dataFim, semanaNum, totalSemanas, sessionsPerDay, whereTrain }
      const ctx = meso_context || {};
      const diasStr = (dias_semana || [])
        .map((d: any) => `  - ${d.date} (${d.day}) | ${d.session_type} | ${d.focoPrincipal} | semana ${d.week}`)
        .join('\n');

      const prompt = `
        Você é o AI Coach do Holy Squat App. Gere os exercícios para a Semana ${ctx.semanaNum} de ${ctx.totalSemanas} do mesociclo "${ctx.nome}".
        [DATA DE HOJE: ${today}]

        [CONTEXTO]
        - Objetivo do macrociclo: ${ctx.objetivo}
        - Mesociclo: ${ctx.nome} | Semana ${ctx.semanaNum}/${ctx.totalSemanas}
        - Foco desta semana: ${ctx.focoSemana || 'Conforme planejamento'}
        - Local de treino: ${JSON.stringify(ctx.whereTrain)}
        - Sessões/dia: ${ctx.sessionsPerDay || 1}

        [DIAS DE TREINO DESTA SEMANA — use exatamente estas datas]
${diasStr}

        [MISSÃO]
        Gere exercícios COMPLETOS para cada dia de treino listado acima.
        - Para cada dia: gere TODOS os exercícios da sessão (aquecimento, principal, metcon, acessório, etc.)
        - NÃO omita exercícios. Seja detalhado e completo.
        - workout_idx: índice sequencial do exercício dentro da sessão (começa em 1).
        - session: número da sessão do dia (normalmente 1, a menos que haja dupla sessão).
        - week = ${ctx.semanaNum} (semana intra-mesociclo).
        - mesocycle = "${ctx.nome}".
        - session_type OBRIGATÓRIO (use apenas tipos da lista): [${allowedSessionTypes}]
        - ANO OBRIGATÓRIO: ${today.split('-')[0]}.

        [FORMATO — JSON PURO SEM MARKDOWN]
        {
          "exerciciosDetalhados": [
            {
              "date": "YYYY-MM-DD",
              "week": ${ctx.semanaNum},
              "mesocycle": "${ctx.nome}",
              "day": "Segunda-feira",
              "session": 1,
              "session_type": "string",
              "duration": 60,
              "workout_idx": 1,
              "exercise": "nome do exercício",
              "exercise_title": "título do bloco",
              "exercise_group": "LPO|Força|Cardio|Mobilidade|etc",
              "exercise_type": "Força|Técnica|Metcon|Acessório|etc",
              "sets": 0,
              "details": "séries × reps @ % ou descrição",
              "time_exercise": 0,
              "ex_unit": "min",
              "rest": 0,
              "rest_unit": "seg",
              "rest_round": 0,
              "rest_round_unit": "min",
              "total_time": 0,
              "location": "Academia",
              "stage": "warmup|workout|cooldown",
              "adaptacaoLesao": ""
            }
          ]
        }
      `;

      console.log(`gerar_exercicios_semana: ${ctx.nome} semana ${ctx.semanaNum}/${ctx.totalSemanas}...`);
      const result = await model.generateContent([prompt]);
      const usage = result.response.usageMetadata;
      console.log(`[TOKENS] semana ${ctx.semanaNum}/${ctx.totalSemanas} | input: ${usage?.promptTokenCount ?? '?'} | output: ${usage?.candidatesTokenCount ?? '?'} | total: ${usage?.totalTokenCount ?? '?'}`);
      const exercData = JSON.parse(result.response.text());
      return new Response(JSON.stringify(exercData), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 })
    }

    // =========================================================
    // AÇÃO: gerar_proximo_meso_fase1
    // 1 chamada Gemini — estrutura + visaoSemanal do próximo meso
    // =========================================================
    else if (acao === 'gerar_proximo_meso_fase1') {
      const planRes = await supabaseClient.from('training_plans').select('*').eq('id', plano_id || '').single();
      const planData = planRes.data || {};
      const startDate = planData.start_date;

      const twelveMonthsBefore = new Date(startDate);
      twelveMonthsBefore.setFullYear(twelveMonthsBefore.getFullYear() - 1);
      const preMacroDateStr = twelveMonthsBefore.toISOString().split('T')[0];

      const [prRes, benchRes, benchDefRes, preWorkoutsRes, preLogsRes, postWorkoutsRes, postLogsRes, profileRes] = await Promise.all([
        supabaseClient.from('pr_log').select('exercise, value, unit, date').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks_logs').select('*').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks').select('*'),
        supabaseClient.from('workouts').select('date, exercise, exercise_title, sets').eq('user_email', email_utilizador).gte('date', preMacroDateStr).lt('date', startDate).order('date', { ascending: false }).limit(50),
        supabaseClient.from('workouts_logs').select('workout_date, weight, reps_done, pse').eq('user_email', email_utilizador).gte('workout_date', preMacroDateStr).lt('workout_date', startDate).order('workout_date', { ascending: false }).limit(50),
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
        - Todos os mesociclos: ${JSON.stringify(todosOsMesos)}
        - Já gerados: ${mesosJaGeradosArr.join(', ') || 'Nenhum'}
        - PRÓXIMO: "${nomeProximoMeso}" — ${duracaoProximoMeso} semanas | ${proximoMeso?.foco || ''}

        [ATLETA]
        - Nome: ${profile.name} | Local: ${JSON.stringify(profile.where_train)}
        - Sessões/dia: ${profile.sessions_per_day}
        - PRs: ${JSON.stringify(prRes.data || [])}
        - Benchmarks: ${JSON.stringify(benchRes.data || [])}
        - Progresso macro (treinos realizados): ${JSON.stringify(postWorkoutsRes.data || [])}
        - Logs PSE: ${JSON.stringify(postLogsRes.data || [])}

        [MISSÃO — ANÁLISE + ESTRUTURA + CALENDÁRIO (sem exercícios detalhados)]
        1. analiseMesocicloAnterior: análise profunda do progresso (aderência, cargas, PSE).
        2. visaoGeralPlano: blocos de todos os mesos (atualize se necessário) + mesociclo1_consolidado
           (${duracaoProximoMeso} linhas — uma por semana do próximo meso).
        3. visaoSemanal: TODOS os 7 dias × ${duracaoProximoMeso} semanas = ${duracaoProximoMeso * 7} entradas.
           - week = intra-mesociclo (começa em 1).
           - mesocycle = "${nomeProximoMeso}".
           - Datas obrigatoriamente entre ${planData.start_date} e ${planData.end_date}.
           - ANO: ${today.split('-')[0]}.
        4. exerciciosDetalhados: [] (VAZIO — gerado por semana separadamente)

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

      console.log("gerar_proximo_meso_fase1: estrutura...");
      const result = await model.generateContent([prompt]);
      const usage = result.response.usageMetadata;
      console.log(`[TOKENS] gerar_proximo_meso_fase1 | input: ${usage?.promptTokenCount ?? '?'} | output: ${usage?.candidatesTokenCount ?? '?'} | total: ${usage?.totalTokenCount ?? '?'}`);
      const fase1Data = JSON.parse(result.response.text());
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
