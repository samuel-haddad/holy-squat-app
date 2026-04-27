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

// ============================================================================
// AUTO-HEALER
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

function parseNotesIntoRestrictions(notes: string): string {
  if (!notes || !notes.trim()) return '';
  const items = notes
    .split(/[;\n]+/)
    .map((s: string) => s.trim())
    .filter((s: string) => s.length > 3);
  if (items.length <= 1) {
    return `    ⚠ Restrição Absoluta: ${notes.trim()}`;
  }
  return items.map((item: string, i: number) => `    ⚠ Restrição ${i + 1}: ${item}`).join('\n');
}

function formatTrainingSessions(sessions: any[]): string {
  if (!sessions || sessions.length === 0) {
    throw new Error("Nenhuma sessão de treino configurada. Por favor, configure suas sessões no perfil ou no onboarding antes de prosseguir.");
  }
  return sessions.map((s: any) => {
    const notesBlock = s.notes
      ? `\n  NOTAS/RESTRIÇÕES ABSOLUTAS:\n${parseNotesIntoRestrictions(s.notes)}`
      : '';
    return `- Sessão ${s.session_number}: Local=[${s.locations?.join(', ')}] | Duração=${s.duration_minutes}min | Dias=[${s.schedule?.join(', ')}] | Turno=${s.time_of_day}${notesBlock}`;
  }).join('\n  ');
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
  const targetTemperature = customTemperature ?? (provider === 'anthropic' ? 0.2 : 0.2);
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
        // On retry attempts for parse errors, use a stricter prompt prefix
        const isRetryAttempt = attempt > 1;
        const systemPrompt = isRetryAttempt
          ? "CRITICAL: Your ENTIRE response MUST be a single valid JSON object. NO text before or after the JSON. NO markdown code fences. NO trailing commas. ALL keys must be double-quoted strings. Start your response with '{' and end with '}'. Nothing else."
          : "You are an AI CrossFit Coach. ALWAYS respond with PURE VALID JSON ONLY. No markdown, no pre-amble, no post-amble. Prohibited: Trailing commas in arrays/objects. Keys must be double-quoted.";

        const anthropicBody: any = {
          model: llmModel,
          max_tokens: isRetryAttempt ? 8000 : 5000,
          temperature: targetTemperature,
          system: systemPrompt,
          messages: [{ role: 'user', content: isRetryAttempt ? prompt + '\n\nIMPORTANT: Respond ONLY with valid JSON. No text before or after the JSON object.' : prompt }],
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

    const adminClient = createClient(supabaseUrl, supabaseServiceKey || supabaseAnonKey)

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

    if (acao === 'gerar_detalhamento') {
      const { email_utilizador, user_id, visao_diaria, exercicios_da_semana, meso_context } = payload;
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

      const diasStr = (visao_diaria || []).map((d: any) => `  - ${d.date} (${d.day}) | session ${d.session || 1} | ${d.session_type} | ${d.focoPrincipal}`).join('\n');
      const exsStr = (exercicios_da_semana || []).map((e: any) => `  - ${e.day}: ${e.exercise} (${e.stage})`).join('\n');

      const ragQuery = `${ctx.focoSemana || ''} ${ctx.objetivo || ''} exercícios crossfit`;
      const knowledgeContext = await queryKnowledgeBase(ragQuery, genAI, adminClient);

      const prompt = `
        ${COACH_PERSONA} Gere os exercícios para o dia especificado abaixo, pertencente à Semana ${ctx.semanaNum} do mesociclo "${ctx.nome}".
        [DATA DE HOJE: ${today}]
        [CONTEXTO CIENTÍFICO (RAG)]
        ${knowledgeContext}
        ${DATA_CONTRACT}
        ${FEW_SHOT_EXAMPLES}
        [TECNICA]
        ${techniqueFeedbacksStr}

        [SESSÕES CONFIGURADAS — CONTRATOS IMUTÁVEIS DO ATLETA]
        As configurações abaixo são CONTRATOS do atleta e NÃO PODEM ser ignoradas:
        - O Local definido em cada sessão é uma RESTRIÇÃO DE INFRAESTRUTURA: os exercícios devem ser compatíveis com o(s) equipamento(s) disponível(is) naquele local. O campo "lo" no output deve refletir exatamente o local da sessão alvo.
        - As Notas são RESTRIÇÕES ABSOLUTAS DE DESIGN: NÃO é permitido gerar exercícios que conflitem com as notas da sessão.
        ${formatTrainingSessions(ctx.trainingSessions || [])}

        [REGRA CRÍTICA — IDENTIDADE DA SESSÃO]
        Você está gerando exercícios APENAS para a sessão identificada pelo campo "session" no [DIA ALVO].
        O campo "se" de TODOS os exercícios gerados DEVE ser IDENTICO ao número de sessão do dia alvo.
        NÃO misture exercícios de sessões diferentes no mesmo output.
        Respeite a duração (du), o local (lo) e as notas da sessão correspondente.
        
        [EXERCÍCIOS JÁ GERADOS NESTA SEMANA (CONTEXTO)]
        ${exsStr || "Nenhum exercício gerado ainda nesta semana."}
        
        [DIA ALVO PARA GERAÇÃO]
${diasStr}

        [FORMATO — JSON COMPACTO]
        { "exs": [{ "dt": "YYYY-MM-DD", "dy": "Dia", "se": 1, "st": "tipo", "du": 60, "idx": 1, "ex": "nome", "et": "titulo", "eg": "grupo", "ey": "tipo_ex", "ts": 3, "de": "detalhes", "te": 0, "eu": "min", "re": 60, "ru": "seg", "tt": 0, "lo": "box", "sg": "workout", "al": "" }] }
        
        [REGRAS RESTRITAS DE JSON E OBJETIVIDADE]
        1. NUNCA coloque vírgulas finais (trailing commas) no último elemento de objetos ou arrays.
        2. Certifique-se de que TODAS as chaves de propriedades tenham aspas duplas ("chave").
        3. SEJA EXTREMAMENTE OBJETIVO. Não inclua NENHUM texto conversacional, explicação ou markdown fora do JSON.
        4. Detalhes ("de") e Títulos ("et") devem ser curtos, diretos e objetivos.
        5. NOMENCLATURA OBRIGATÓRIA: O campo "st" (session_type) DEVE usar EXCLUSIVAMENTE os valores em PORTUGUÊS da lista fornecida. PROIBIDO usar nomes em inglês (ex: "Force-Metcon" é INVÁLIDO → use "Força-Metcon"). Use EXATAMENTE um dos valores listados em [RESTRIÇÃO DE NOMENCLATURA].
      `;

      const responseData = await generateWithProvider(prompt, provider, llmModel, genAI, `detalhamento_s${ctx.semanaNum}`, 16000, 0.2);

      const fullExercicios = await Promise.all((responseData.exs || []).map(async (short: any) => {
        const { data: link } = await adminClient.rpc('get_closest_exercise_link', { search_name: short.et || short.ex });
        const ts = Number(short.ts) || 1;
        const te = Number(short.te) || 0;
        const re = Number(short.re) || 0;
        const teMin = (short.eu === "seg") ? te / 60 : te;
        const reMin = (short.ru === "seg") ? re / 60 : re;
        const tt_final = Number(((teMin * ts) + (reMin * Math.max(0, ts - 1))).toFixed(1));

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
