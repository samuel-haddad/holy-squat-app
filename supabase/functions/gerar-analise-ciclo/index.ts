import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI, HarmCategory, HarmBlockThreshold } from "npm:@google/generative-ai"

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

// ============================================================================
// AUTO-HEALER: Reconstrói JSONs truncados usando Pilha (Stack)
// ============================================================================
function autoHealJSON(str: string): string {
  let text = str.trim();
  const start = text.search(/[\{\[]/);
  if (start === -1) return str;
  text = text.substring(start);

  let stack: string[] = [];
  let inString = false;
  let escape = false;

  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (escape) { escape = false; continue; }
    if (char === '\\') { escape = true; continue; }
    if (char === '"') { inString = !inString; continue; }
    if (!inString) {
      if (char === '{' || char === '[') stack.push(char);
      else if (char === '}') { if (stack.length > 0 && stack[stack.length - 1] === '{') stack.pop(); }
      else if (char === ']') { if (stack.length > 0 && stack[stack.length - 1] === '[') stack.pop(); }
    }
  }

  let healed = text;
  if (inString) healed += '"';
  while (stack.length > 0) {
    const last = stack.pop();
    if (last === '{') healed += '}';
    else if (last === '[') healed += ']';
  }
  return healed;
}

function extractRobustJSON(str: string): any {
  let text = str.trim();
  text = text.replace(/```(json)?/gi, '').trim();

  try { return JSON.parse(text); } catch (_) { }

  try {
    const healed = autoHealJSON(text);
    return JSON.parse(healed);
  } catch (_) { }

  let currentStr = text.replace(/,\s*([\]}])/g, '$1');
  const start = currentStr.search(/[\{\[]/);
  if (start !== -1) currentStr = currentStr.substring(start);

  while (currentStr.length > 0) {
    try {
      return JSON.parse(currentStr);
    } catch (e: any) {
      const lastBrace = currentStr.lastIndexOf('}', currentStr.length - 2);
      const lastBracket = currentStr.lastIndexOf(']', currentStr.length - 2);
      const lastValid = Math.max(lastBrace, lastBracket);
      if (lastValid === -1) break;
      currentStr = currentStr.substring(0, lastValid + 1);
    }
  }
  throw new Error("Não foi possível extrair um JSON válido mesmo com Auto-Heal.");
}

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
  maxTokens: number = 16000,
  customTemperature?: number
): Promise<any> {
  const targetTemperature = customTemperature ?? (provider === 'anthropic' ? 0.2 : 0.7);
  const maxRetries = 2;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (provider === 'google') {
        const model = genAI.getGenerativeModel(
          {
            model: llmModel,
            systemInstruction: { role: "system", parts: [{ text: "You are an AI CrossFit Coach. ALWAYS respond with PURE VALID JSON ONLY. No markdown, no pre-amble, no post-amble." }] },
            generationConfig: {
              temperature: targetTemperature,
              maxOutputTokens: maxTokens,
              responseMimeType: "application/json"
            },
            safetySettings: [
              { category: HarmCategory.HARM_CATEGORY_HARASSMENT, threshold: HarmBlockThreshold.BLOCK_NONE },
              { category: HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold: HarmBlockThreshold.BLOCK_NONE },
              { category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold: HarmBlockThreshold.BLOCK_NONE },
              { category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: HarmBlockThreshold.BLOCK_NONE }
            ]
          },
          { apiVersion: 'v1beta' }
        );
        const result = await model.generateContent([prompt]);
        const rawText = result.response.text();

        try {
          return extractRobustJSON(rawText);
        } catch (e: any) {
          throw new Error(`JSON Parse falhou no provider Google (${actionLabel}): ${e.message}`);
        }

      } else if (provider === 'anthropic') {
        const anthropicBody: any = {
          model: llmModel,
          max_tokens: maxTokens,
          temperature: targetTemperature,
          system: "You are an AI CrossFit Coach. ALWAYS respond with PURE VALID JSON ONLY. No markdown, no pre-amble, no post-amble. Prohibited: Trailing commas in arrays/objects. Keys must be double-quoted.",
          messages: [{ role: 'user', content: prompt }],
        };

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
          if (response.status === 429) throw new Error(`429: ${JSON.stringify(data)}`);
          throw new Error(`Anthropic API error (${response.status}): ${JSON.stringify(data)}`);
        }

        const rawText: string = data.content[0].text;

        try {
          return extractRobustJSON(rawText);
        } catch (e: any) {
          throw new Error(`Invalid JSON from Claude at ${actionLabel}: ${e.message}`);
        }

      } else {
        throw new Error(`Provider desconhecido: ${provider}`);
      }

    } catch (err: any) {
      const errorText = err.message || '';
      const isRateLimit = errorText.includes('429') || errorText.toLowerCase().includes('quota') || errorText.toLowerCase().includes('limit');
      const isParseError = errorText.includes('JSON Parse falhou') || errorText.includes('Invalid JSON') || errorText.includes('Parse falhou') || errorText.includes('Não foi possível extrair um JSON');

      if (isRateLimit && attempt < maxRetries) {
        console.warn(`[RETRY ${attempt}/${maxRetries}] Rate Limit detectado. Aguardando...`);
        await sleep(attempt * 3500);
        continue;
      }
      if (isParseError && attempt < maxRetries) {
        console.warn(`[RETRY ${attempt}/${maxRetries}] JSON truncado/quebrado. Retentativa imediata... (${errorText.substring(0, 100)})`);
        continue;
      }
      throw err;
    }
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() || '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim() || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() || '';
    const geminiKey = Deno.env.get('GEMINI_API_KEY')?.trim() || '';

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

    if (acao === 'gerar_analise') {
      const { email_utilizador, user_id, bloco_atual, performance_stats, cycle_snapshot, training_sessions, contexto_macrociclo } = payload;
      const profileRes = user_id
        ? await adminClient.from('profiles').select('*').eq('id', user_id).single()
        : await adminClient.from('profiles').select('*').eq('email', email_utilizador).single();

      const profile = profileRes.data || {};
      const bloco = bloco_atual || {};
      const perfStats = performance_stats || {};
      const cycleSnap = cycle_snapshot || null;
      const sessions = training_sessions || [];
      const macroCtx = contexto_macrociclo || {};

      let techniqueFeedbacksStr = "Nenhum feedback de técnica registrado.";
      if (profile?.id) {
        const { data: tfData } = await adminClient.from('technique_feedbacks').select('exercise_name, resume_text').eq('user_id', profile.id).order('created_at', { ascending: false });
        if (tfData && tfData.length > 0) techniqueFeedbacksStr = tfData.map((tf: any) => `- Exercício: ${tf.exercise_name}\n  Análise: ${tf.resume_text}`).join('\n');
      }

      const prompt = `
        ${COACH_PERSONA}
        [MISSÃO — ANÁLISE E PLANEJAMENTO DO MESOCICLO]
        ${payload.model_observations ? `\n        [OBSERVAÇÕES DO MODELO]\n        ${payload.model_observations}\n` : ''}
        Gere apenas 1 componente essencial:
        1. analiseCicloAnterior: Avaliação do progresso.

        ${METRICS_DEFINITIONS}

        [CONTEXTO DO ATLETA]
        - Nome: ${profile.name} | Objetivo Macro: ${macroCtx.visao_geral_plano?.objetivoPrincipal || 'N/A'}
        - Histórico/Análise Macro: ${macroCtx.analise_historica?.analiseMacro?.analise || 'N/A'}
        - Técnica: ${techniqueFeedbacksStr}
        
        [MESOCICLO ATUAL]
        - Nome: ${bloco.mesociclo} | Foco Original: ${bloco.foco}

        [DADOS PARA ANÁLISE DE PROGRESSO]
        - KPIs Ciclo Anterior: ${JSON.stringify(perfStats?.kpis || perfStats || {})}
        - Snapshot Atual: ${JSON.stringify(cycleSnap?.kpis || {})}

        [REGRAS DE RESPOSTA]
        - SEJA ULTRA OBJETIVO. Sem introduções.
        - analiseCicloAnterior: Texto narrativo em 'texto'.

        [FORMATO — JSON]
        {
          "analiseCicloAnterior": { "texto": "string" }
        }
      `;

      const result = await generateWithProvider(prompt, provider, llmModel, genAI, 'gerar_analise', 4000, 0.7);
      


      return new Response(JSON.stringify(result), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    else if (acao === 'gerar_calendario') {
      const { bloco_atual, visao_geral, data_inicio_meso, training_sessions } = payload;
      const bloco = bloco_atual || {};
      const sessions = training_sessions || [];

      const promptGeral = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]
        [DATA DE INÍCIO DO MESOCICLO: ${data_inicio_meso || today}]
        [MISSÃO — GERAR VISÃO GERAL DO MESOCICLO]
        Gere a visão macroscópica de cada semana do ciclo.
        1. visaoGeralCiclo: A lista de objetos deve ter EXATAMENTE ${bloco.duracaoSemanas || 4} semanas de duração. Cada objeto deve conter o foco da semana e uma descrição detalhada do que deve ser feito em cada dia (seg a dom).
        2. resumoMesociclo: Apenas repita a definição do foco deste bloco.
        
        [BLOCO ATUAL DO MESOCICLO]
        - Nome: ${bloco.mesociclo} | Foco: ${bloco.foco} | Duração: ${bloco.duracaoSemanas || 4} semanas

        [FORMATO — JSON]
        {
          "visaoGeralCiclo": [{ "semana": 1, "foco": "string", "seg": "string", "ter": "string", "qua": "string", "qui": "string", "sex": "string", "sab": "string", "dom": "string" }],
          "resumoMesociclo": "string"
        }

        [DIRETRIZES DE RECOVERY]
        - Importante: Dias de descanso e descanso ativo podem ocorrer em dias que também possuem sessões de treino, se a metodologia julgar pertinente.
      `;
      console.log("[gerar_calendario] Solicitando visão geral (etapa 1/2)...");
      const resultGeral = await generateWithProvider(promptGeral, provider, llmModel, genAI, 'gerar_calendario_geral', 8000, 0.2);

      const promptSemanal = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]
        [DATA DE INÍCIO DO MESOCICLO: ${data_inicio_meso || today}]
        [MISSÃO — GERAR VISÃO SEMANAL DETALHADA]
        Baseado na visão macroscópica já definida, distribua os treinos exatos nas datas corretas seguindo a rotina de sessões configuradas do atleta.
        1. visaoSemanal: O calendário detalhado de treinos para TODAS AS ${bloco.duracaoSemanas || 4} SEMANAS.
        ATENÇÃO: É obrigatório que o array visaoSemanal contenha os treinos de TODAS as semanas descritas na Visão Geral, sem deixar nenhum 'focoPrincipal' em branco.
        
        [VISÃO GERAL DO CICLO (Use isso como guia de conteúdo e duração)]
        ${JSON.stringify(resultGeral.visaoGeralCiclo)}
        
        [SESSÕES CONFIGURADAS (ROTINA DO ATLETA)]
        ${formatTrainingSessions(sessions)}
        
        [BLOCO ATUAL DO MESOCICLO]
        - Nome: ${bloco.mesociclo} | Duração: ${bloco.duracaoSemanas || 4} semanas

        [FORMATO — JSON]
        {
          "visaoSemanal": [{ "date": "YYYY-MM-DD", "session": 1, "session_type": "string", "focoPrincipal": "string" }]
        }

        [DIRETRIZES DE RECOVERY]
        - Lembre-se: Descansos e descansos ativos podem coexistir com sessões de treino no mesmo dia. Se o atleta treina mas também precisa de recuperação ativa, ambos devem ser listados para a mesma data.
      `;
      console.log("[gerar_calendario] Solicitando visão semanal (etapa 2/2)...");
      const resultSemanal = await generateWithProvider(promptSemanal, provider, llmModel, genAI, 'gerar_calendario_semanal', 8000, 0.2);

      const result = {
        visaoGeralCiclo: resultGeral.visaoGeralCiclo,
        resumoMesociclo: resultGeral.resumoMesociclo,
        visaoSemanal: resultSemanal.visaoSemanal
      };

      if (result.visaoSemanal && Array.isArray(result.visaoSemanal)) {
        const diasSemana = ["Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado"];

        // Resgate da definição tal qual (foco do bloco)
        result.resumoMesociclo = bloco.foco || result.resumoMesociclo;

        const duracaoSemanas = (result.visaoGeralCiclo && result.visaoGeralCiclo.length > 0) ? result.visaoGeralCiclo.length : 4;
        const totalDias = duracaoSemanas * 7;

        let startD = new Date();
        if (data_inicio_meso) {
          startD = new Date(data_inicio_meso + 'T12:00:00Z');
        } else if (result.visaoSemanal.length > 0) {
          startD = new Date(result.visaoSemanal[0].date + 'T12:00:00Z');
        }

        const mapDiasAtivos = new Map();
        result.visaoSemanal.forEach((dia: any) => {
          if (!mapDiasAtivos.has(dia.date)) {
            mapDiasAtivos.set(dia.date, []);
          }
          mapDiasAtivos.get(dia.date).push(dia);
        });

        const visaoCompleta = [];
        for (let i = 0; i < totalDias; i++) {
          const d = new Date(startD.getTime() + i * 24 * 60 * 60 * 1000);
          const dateStr = d.toISOString().split('T')[0];
          const dayName = diasSemana[d.getUTCDay()];
          const weekNum = Math.floor(i / 7) + 1;

          if (mapDiasAtivos.has(dateStr)) {
            const itensDoDia = mapDiasAtivos.get(dateStr);
            itensDoDia.forEach((diaObj: any) => {
              visaoCompleta.push({
                ...diaObj,
                day: dayName,
                mesocycle: bloco.mesociclo,
                week: weekNum,
                isDescansoAtivo: diaObj.session_type === "Descanso" || diaObj.session_type === "Recuperação Ativa"
              });
            });
          } else {
            visaoCompleta.push({
              date: dateStr,
              session: 1,
              session_type: "Descanso",
              focoPrincipal: "Recuperação",
              day: dayName,
              mesocycle: bloco.mesociclo,
              week: weekNum,
              isDescansoAtivo: true
            });
          }
        }

        result.visaoSemanal = visaoCompleta;
      }
      return new Response(JSON.stringify(result), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    else return new Response(JSON.stringify({ error: `Ação desconhecida: ${acao}` }), { headers: corsHeaders, status: 400 })

  } catch (error) {
    console.error("Erro Edge Function:", error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 });
  }
})
