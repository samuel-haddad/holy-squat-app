import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI } from "npm:@google/generative-ai"
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const workoutSchemaTemplate = `
Você DEVE retornar APENAS um JSON válido seguindo a estrutura exata (sem markdown como \`\`\`json):
{
  "analiseMacro": { "analise": "string (opcional)" },
  "analiseMesocicloAnterior": { "aderencia": "string", "evolucao": "string" },
  "visaoGeralPlano": { "objetivoPrincipal": "string", "duracaoSemanas": 0 },
  "visaoSemanal": [
    { "date": "YYYY-MM-DD", "day": "Segunda-feira", "session_type": "string", "focoPrincipal": "string", "isDescansoAtivo": false }
  ],
  "exerciciosDetalhados": [
    {
      "date": "YYYY-MM-DD",
      "week": 1,
      "mesocycle": "string",
      "day": "Segunda-feira",
      "session": 1,
      "session_type": "string",
      "duration": 60,
      "workout_idx": 1,
      "exercise": "Back Squat",
      "exercise_title": "Força",
      "exercise_group": "LPO",
      "exercise_type": "Força",
      "sets": 5,
      "details": "5x5 @ 70%",
      "time_exercise": 15,
      "ex_unit": "min",
      "rest": 90,
      "rest_unit": "seg",
      "rest_round": 0,
      "rest_round_unit": "min",
      "total_time": 15,
      "location": "Academia",
      "stage": "workout",
      "adaptacaoLesao": "string (opcional)"
    }
  ]
}`;

const allowedSessionTypes = "Acessório, Acessórios/Blindagem, Calistenia, Cardio, Cardio-Mobilidade, Core Strength, Core/Prep, Crossfit, Descanso, Endurance, Força/Heavy, Força/Metcon, Força/Skill, Full Body Pump, Full Session, Ginástica/Metcon, Hipertrofia/Blindagem, LPO, LPO/Força/Metcon, LPO/Metcon, LPO/Potência, Mobilidade, Mobilidade Flow, Mobilidade-Cardio, Mobilidade-Core, Mobilidade-Inferiores, Mobilidade/Prep, Multi, Musculação, Musculação-Cardio, Musculação-Funcional, Musculação/Força, Natação, Prehab/Força, Prehab/Mobilidade, Recuperação Ativa, Reintrodução/FBB, Skill, Skill/Metcon";

async function queryKnowledgeBase(queryText: string, genAI: any, supabaseClient: any) {
  if (!queryText) return "";
  try {
    // Utilizado 'text-embedding-004' (recomendado) ou fallback para o modelo de ingestão
    const embeddingModel = genAI.getGenerativeModel({ model: "text-embedding-004" });
    const result = await embeddingModel.embedContent(queryText);
    const embedding = result.embedding.values;

    const { data: documents, error } = await supabaseClient.rpc('match_knowledge_base', {
      query_embedding: embedding,
      match_threshold: 0.4, // Threshold mais baixo para recuperar contexto relacionado a lesão/rehab
      match_count: 5 // top 5 blocos (chunks)
    });

    if (error) {
      console.error("RPC Error (match_knowledge_base):", error);
      return "";
    }

    if (documents && documents.length > 0) {
      const texts = documents.map((doc: any) => doc.content).join("\n\n---\n\n");
      return `\n[LITERATURA CIENTÍFICA DE REFERÊNCIA (KNOWLEDGE BASE)]\nVocê DEVE basear seu raciocínio anatômico e prescrição de treino nas diretrizes abaixo. Use essas informações para pautar qualquer adaptação de lesão ou de foco que o atleta pedir:\n\n${texts}\n`;
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
    const { acao, email_utilizador, diretrizes_plano, plano_id, semana_alvo, mesociclo_atual, foco_semana } = payload

    const genAI = new GoogleGenerativeAI(Deno.env.get('GEMINI_API_KEY')!)
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash", generationConfig: { responseMimeType: "application/json" } })

    if (acao === 'criar_plano_macro') {
      // 1. Fetch User Context from DB
      const [profileRes, prRes, benchRes] = await Promise.all([
        supabaseClient.from('profiles').select('*').eq('email', email_utilizador).single(),
        supabaseClient.from('pr_log').select('*').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks_logs').select('*').eq('user_email', email_utilizador)
      ]);

      const profile = profileRes.data || {};
      const prs = prRes.data || [];
      const benchmarks = benchRes.data || [];

      // 2. Try fetching the Background PDF if it exists
      let pdfPart = null;
      if (profile.background_file_url) {
        try {
          const pdfResponse = await fetch(profile.background_file_url);
          if (pdfResponse.ok) {
            const arrayBuffer = await pdfResponse.arrayBuffer();
            const uint8Array = new Uint8Array(arrayBuffer);
            const base64Pdf = encodeBase64(uint8Array);

            pdfPart = {
              inlineData: {
                data: base64Pdf,
                mimeType: "application/pdf"
              }
            };
          }
        } catch (e) { console.error("Could not fetch background PDF", e); }
      }

      const promptText = `
        Você é o AI Coach especialista em periodização de CrossFit do Holy Squat App.
        Crie um planejamento Macro para o atleta com base nos seguintes dados:

        [PERFIL E HISTÓRICO]
        - Nome/Email: ${profile.name} / ${email_utilizador}
        - Treina em: ${JSON.stringify(profile.where_train)}
        - Treinos semanais p/ dia: ${profile.sessions_per_day} | Duração: ${profile.active_hours_value} ${profile.active_hours_unit}
        - PRs Recentes: ${JSON.stringify(prs)}
        - Benchmarks: ${JSON.stringify(benchmarks)}

        [DIRETRIZES DO NOVO PLANO]
        - Objetivo: ${diretrizes_plano?.objetivo}
        - Início do plano: ${diretrizes_plano?.data_inicio}
        - Fim do plano: ${diretrizes_plano?.data_fim}
        - Competições alvo: ${JSON.stringify(diretrizes_plano?.competicoes)}
        - Notas adicionais: ${diretrizes_plano?.notas}
        
        ${await queryKnowledgeBase(diretrizes_plano?.objetivo || "", genAI, supabaseClient)}
        
        [INSTRUÇÕES]
        Gere uma 'analiseMacro' sobre o atleta baseada nos dados.
        Gere a 'visaoGeralPlano'. É OBRIGATÓRIO preencher o array "blocos" com TODOS os mesociclos que compõem o plano inteiro (ex: Adaptação 4 sem, Hipertrofia 4 sem, etc). O array "blocos" não pode estar vazio!
        ATENÇÃO: Devido a limites técnicos (Tokens), para a "visaoSemanal" e "exerciciosDetalhados", 
        GERE EXCLUSIVAMENTE A SEMANA 1 (microciclo 1)! Retorne os 7 dias exatos. Não tente gerar as 4 semanas aqui.
        
        OBRIGATÓRIO: O campo "session_type" (em visaoSemanal e exerciciosDetalhados) DEVE SER EXATAMENTE um dos seguintes valores (respeite maiúsculas e minúsculas):
        [${allowedSessionTypes}]

        ${workoutSchemaTemplate}
      `;

      const promptParts: any[] = [promptText];
      if (pdfPart) {
        promptParts.push(pdfPart);
      }

      const result = await model.generateContent(promptParts);
      const output = result.response.text();
      const planData = JSON.parse(output);

      return new Response(JSON.stringify(planData), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 })
    }
    else if (acao === 'gerar_semana_micro') {
      const [planRes, prRes, benchRes] = await Promise.all([
        supabaseClient.from('training_plans').select('*').eq('id', plano_id || '').single(),
        supabaseClient.from('pr_log').select('*').eq('user_email', email_utilizador),
        supabaseClient.from('benchmarks_logs').select('*').eq('user_email', email_utilizador)
      ]);

      const planData = planRes.data || {};
      const prs = prRes.data || [];
      const benchmarks = benchRes.data || [];

      const prompt = `
        Você é o AI Coach especialista em periodização de CrossFit.
        Gere detalhadamente o Planejamento Microciclo para o Mesociclo (${mesociclo_atual}, Semana ${semana_alvo}).
        Foco da semana: ${foco_semana}

        [CONTEXTO DO ATLETA]
        - Plano Macro (Diretrizes Iniciais): ${JSON.stringify(planData)}
        - Lista de PRs (Recordes Pessoais): ${JSON.stringify(prs)}
        - Benchmarks atuais: ${JSON.stringify(benchmarks)}
        
        ${await queryKnowledgeBase(foco_semana || "", genAI, supabaseClient)}

        [REGRAS]
        1. Analise a evolução do histórico e prepare a próxima semana (Microciclo).
        2. Atualize a 'visaoSemanal' EXCLUSIVAMENTE PARA ESTA PRÓXIMA SEMANA (7 dias).
        3. Forneça os blocos de treinos apenas desta semana na lista de 'exerciciosDetalhados' adaptada às cargas e PRs dele.
        4. OBRIGATÓRIO: O campo "session_type" DEVE SER EXATAMENTE um dos seguintes valores: [${allowedSessionTypes}]
        
        ${workoutSchemaTemplate}
      `;

      const result = await model.generateContent([prompt]);
      const output = result.response.text();
      const weekData = JSON.parse(output);

      return new Response(JSON.stringify(weekData), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 })
    }
    else {
      return new Response(JSON.stringify({ error: 'Ação desconhecida.' }), { headers: corsHeaders, status: 400 })
    }

  } catch (error) {
    console.error("Erro no Edge Function:", error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500
    });
  }
})
