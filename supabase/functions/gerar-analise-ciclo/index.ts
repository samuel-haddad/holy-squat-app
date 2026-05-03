import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { GoogleGenerativeAI, HarmCategory, HarmBlockThreshold } from "npm:@google/generative-ai"

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

function normalizeDayName(day: string): string {
  const m: Record<string, string> = {
    'seg': 'Segunda-feira', 'segunda': 'Segunda-feira', 'segunda-feira': 'Segunda-feira',
    'ter': 'Terça-feira', 'terca': 'Terça-feira', 'terça': 'Terça-feira', 'terça-feira': 'Terça-feira',
    'qua': 'Quarta-feira', 'quarta': 'Quarta-feira', 'quarta-feira': 'Quarta-feira',
    'qui': 'Quinta-feira', 'quinta': 'Quinta-feira', 'quinta-feira': 'Quinta-feira',
    'sex': 'Sexta-feira', 'sexta': 'Sexta-feira', 'sexta-feira': 'Sexta-feira',
    'sab': 'Sábado', 'sabado': 'Sábado', 'sábado': 'Sábado',
    'dom': 'Domingo', 'domingo': 'Domingo',
  };
  return m[day.toLowerCase()] || day;
}

function validateVisaoSemanal(
  visaoSemanal: any[],
  sessions: any[],
  dataInicioMeso?: string,
  duracaoSemanas?: number
): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  if (!sessions || sessions.length === 0) return { valid: true, errors };

  const diasSemanaArr = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado'];

  const dayToExpected: Record<string, number[]> = {};
  for (const s of sessions) {
    for (const day of (s.schedule || [])) {
      const norm = normalizeDayName(day);
      if (!dayToExpected[norm]) dayToExpected[norm] = [];
      dayToExpected[norm].push(Number(s.session_number));
    }
  }

  // Build set of all generated (date_session) pairs — skip pure Descanso
  const generatedPairs = new Set<string>();
  for (const entry of visaoSemanal) {
    if (entry.session_type === 'Descanso') continue;
    generatedPairs.add(`${entry.date}_${entry.session}`);
  }

  if (dataInicioMeso && duracaoSemanas && duracaoSemanas > 0) {
    // FULL COVERAGE: verifica cada (data, sessão) esperado no mesociclo inteiro
    const startD = new Date(dataInicioMeso + 'T12:00:00Z');
    const totalDias = duracaoSemanas * 7;
    for (let i = 0; i < totalDias; i++) {
      const d = new Date(startD.getTime() + i * 24 * 60 * 60 * 1000);
      const dateStr = d.toISOString().split('T')[0];
      const dayName = diasSemanaArr[d.getUTCDay()];
      for (const expSession of (dayToExpected[dayName] || [])) {
        if (!generatedPairs.has(`${dateStr}_${expSession}`)) {
          errors.push(`${dateStr} (${dayName}): Sessão ${expSession} foi omitida`);
        }
      }
    }
  } else {
    // FALLBACK: verifica apenas datas que aparecem no resultado
    const dateToGenerated: Record<string, Set<number>> = {};
    for (const entry of visaoSemanal) {
      if (entry.session_type === 'Descanso') continue;
      if (!dateToGenerated[entry.date]) dateToGenerated[entry.date] = new Set();
      dateToGenerated[entry.date].add(Number(entry.session));
    }
    for (const [date, generatedSet] of Object.entries(dateToGenerated)) {
      const d = new Date(date + 'T12:00:00Z');
      const dayName = diasSemanaArr[d.getUTCDay()];
      for (const expSession of (dayToExpected[dayName] || [])) {
        if (!generatedSet.has(expSession)) {
          errors.push(`${date} (${dayName}): Sessão ${expSession} foi omitida`);
        }
      }
    }
  }

  return { valid: errors.length === 0, errors };
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

// Constrói a lista obrigatória de entradas (date × session) para o prompt da visão semanal
function buildRequiredEntriesList(dataInicioMeso: string, duracaoSemanas: number, sessions: any[]): string {
  if (!dataInicioMeso || !sessions || sessions.length === 0) return '';
  const diasSemanaArr = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado'];
  const dayToSessions: Record<string, number[]> = {};
  for (const s of sessions) {
    for (const day of (s.schedule || [])) {
      const norm = normalizeDayName(day);
      if (!dayToSessions[norm]) dayToSessions[norm] = [];
      dayToSessions[norm].push(Number(s.session_number));
    }
  }
  const startD = new Date(dataInicioMeso + 'T12:00:00Z');
  const lines: string[] = [];
  for (let i = 0; i < duracaoSemanas * 7; i++) {
    const d = new Date(startD.getTime() + i * 24 * 60 * 60 * 1000);
    const dateStr = d.toISOString().split('T')[0];
    const dayName = diasSemanaArr[d.getUTCDay()];
    for (const sn of (dayToSessions[dayName] || [])) {
      lines.push(`        { "date": "${dateStr}", "session": ${sn} }  ← ${dayName}`);
    }
  }
  return lines.join('\n');
}

// Trunca o focoPrincipal para exibição concisa (~30 palavras) preservando contexto semântico
function truncateFocoPrincipal(text: string, maxWords = 30): string {
  if (!text) return text;
  const words = text.trim().split(/\s+/);
  if (words.length <= maxWords) return text;
  return words.slice(0, maxWords).join(' ') + '... [Resumido]';
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

      const orientacaoExtraStr = payload.orientacao_extra ? `\n        [ORIENTAÇÃO EXTRA DO USUÁRIO PARA ESTE CICLO]\n        ${payload.orientacao_extra}\n        INSTRUÇÃO CRÍTICA: Você DEVE considerar esta orientação ao fazer a análise e planejar os próximos passos.\n` : '';

      const prompt = `
        ${COACH_PERSONA}
        [MISSÃO — ANÁLISE E PLANEJAMENTO DO MESOCICLO]
        ${payload.model_observations ? `\n        [OBSERVAÇÕES DO MODELO]\n        ${payload.model_observations}\n` : ''}${orientacaoExtraStr}
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

      const mapSessoesPorDia = new Map<string, number>();
      let totalSessoesConfiguradas = 0;
      sessions.forEach((s: any) => {
        (s.schedule || []).forEach((d: string) => {
          const lower = String(d).toLowerCase();
          let key = "";
          if (lower.includes('seg')) key = 'seg';
          else if (lower.includes('ter')) key = 'ter';
          else if (lower.includes('qua')) key = 'qua';
          else if (lower.includes('qui')) key = 'qui';
          else if (lower.includes('sex')) key = 'sex';
          else if (lower.includes('sab')) key = 'sab';
          else if (lower.includes('dom')) key = 'dom';

          if (key) {
            if (!mapSessoesPorDia.has(key)) mapSessoesPorDia.set(key, 0);
            mapSessoesPorDia.set(key, mapSessoesPorDia.get(key)! + 1);
            totalSessoesConfiguradas++;
          }
        });
      });

      let mapaTexto = "";
      mapSessoesPorDia.forEach((qty, day) => {
        mapaTexto += `        - ${day.toUpperCase()}: ${qty} sessão(ões) configurada(s)\n`;
      });
      const diasAtivosExtenso = Array.from(mapSessoesPorDia.keys()).join(', ').toUpperCase();

      const orientacaoExtraStr = payload.orientacao_extra ? `\n        [ORIENTAÇÃO EXTRA DO USUÁRIO PARA ESTE CICLO]\n        ${payload.orientacao_extra}\n        INSTRUÇÃO CRÍTICA: Você DEVE considerar e priorizar esta orientação no planejamento das sessões.\n` : '';

      const promptGeral = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]
        [DATA DE INÍCIO DO MESOCICLO: ${data_inicio_meso || today}]
        [MISSÃO — GERAR VISÃO GERAL DO MESOCICLO]${orientacaoExtraStr}
        Gere a visão macroscópica de cada semana do ciclo.
        1. visaoGeralCiclo: A lista de objetos deve ter EXATAMENTE ${bloco.duracaoSemanas || 4} semanas de duração. Cada objeto deve conter o foco da semana e os blocos de treino macroscópicos para cada dia (seg a dom).
        2. resumoMesociclo: Apenas repita a definição do foco deste bloco.

        [RESTRIÇÃO DE ESCOPO — VISÃO MACRO E BUDGETING MENTAL]
        1. PROIBIDO MICRO-PLANEJAMENTO: É ESTRITAMENTE PROIBIDO listar exercícios específicos (ex: Front Squat, Pull-ups, Corrida de 5km, etc), séries, repetições, distâncias ou tempos de execução.
        2. FOCO EM INTENÇÃO GERAL: Descreva APENAS os grupos musculares, capacidades físicas ou intenções do bloco (Ex: "Força de Membros Inferiores + Ginástica Básica", ou "LPO (Snatch) + Condicionamento Metabólico Curto", ou "Corrida Curta", ou "Longão", ou "METCON")).
        3. PROIBIDO ESTIMAR O TEMPO DOS EXERCÍCIOS.
        
        [BLOCO ATUAL DO MESOCICLO]
        - Nome: ${bloco.mesociclo} | Foco: ${bloco.foco} | Duração: ${bloco.duracaoSemanas || 4} semanas

        [SESSÕES CONFIGURADAS - DIAS DISPONÍVEIS]
        ${formatTrainingSessions(sessions)}

        [FORMATO — JSON]
        {
          "visaoGeralCiclo": [{ "semana": 1, "foco": "string", "seg": "string", "ter": "string", "qua": "string", "qui": "string", "sex": "string", "sab": "string", "dom": "string" }],
          "resumoMesociclo": "string"
        }

        [MAPA EXATO DE DISPONIBILIDADE DO ATLETA]
        O atleta possui EXATAMENTE ${totalSessoesConfiguradas} sessões na semana, distribuídas da seguinte forma:
${mapaTexto}
        
        [DIRETRIZES DE TREINO E DESCANSO - CUMPRIMENTO OBRIGATÓRIO]
        1. Você DEVE preencher as chaves JSON dos dias ativos (${diasAtivosExtenso}) com a descrição MACROSCÓPICA dos TREINOS ATIVOS. Se o dia tiver 2 sessões, descreva a intenção das DUAS.
        2. Os dias que não constam no Mapa Exato são os verdadeiros dias de descanso do atleta. Nesses, você deve escrever "Descanso".
      `;
      console.log("[gerar_calendario] Solicitando visão geral (etapa 1/2)...");
      const resultGeral = await generateWithProvider(promptGeral, provider, llmModel, genAI, 'gerar_calendario_geral', 8000, 0.2);

      const duracaoSemanas = bloco.duracaoSemanas || (resultGeral.visaoGeralCiclo?.length) || 4;
      const dataInicio = data_inicio_meso || today;
      const requiredEntriesList = buildRequiredEntriesList(dataInicio, duracaoSemanas, sessions);

      const MAX_SEMANAL_RETRIES = 3;
      let resultSemanal: any = null;

      for (let attempt = 1; attempt <= MAX_SEMANAL_RETRIES; attempt++) {
        const retryNote = attempt > 1
          ? `\n        [⚠️ TENTATIVA ${attempt}/${MAX_SEMANAL_RETRIES} — CORREÇÃO OBRIGATÓRIA]\n        Na tentativa anterior, sessões foram OMITIDAS. Gere TODAS as entradas da lista obrigatória abaixo sem exceção.\n`
          : '';

        const promptSemanal = `
        ${COACH_PERSONA}
        [DATA DE HOJE: ${today}]
        [DATA DE INÍCIO DO MESOCICLO: ${dataInicio}]
        [MISSÃO — GERAR VISÃO SEMANAL DETALHADA]${orientacaoExtraStr}
        Baseado na visão macroscópica já definida, distribua os treinos exatos nas datas corretas seguindo a rotina de sessões configuradas do atleta.
        1. visaoSemanal: O calendário detalhado de treinos para TODAS AS ${duracaoSemanas} SEMANAS.
        ATENÇÃO: É obrigatório que o array visaoSemanal contenha os treinos de TODAS as semanas descritas na Visão Geral, sem deixar nenhum 'focoPrincipal' em branco.
        ${retryNote}
        [VISÃO GERAL DO CICLO (Use isso como guia de conteúdo e duração)]
        ${JSON.stringify(resultGeral.visaoGeralCiclo)}

        [REGRA CRÍTICA — SESSÕES POR DIA]
        Para cada dia da semana em que uma ou mais sessões estão configuradas, você DEVE gerar UMA entrada no visaoSemanal POR SESSÃO.
        Se o atleta tem Sessão 1 e Sessão 2 na Segunda-feira, o visaoSemanal deve conter DOIS objetos com "date": "YYYY-MM-DD", sendo "session": 1 e "session": 2 respectivamente.
        NUNCA omita uma sessão configurada, mesmo que seja uma sessão de Descanso ou Recuperação Ativa.

        [REQUISITO DE RESUMO — CRÍTICO]
        Cada 'focoPrincipal' DEVE ser um resumo técnico extremamente conciso (MÁXIMO 30 PALAVRAS).
        Foque no QUE será feito, eliminando descrições verbosas.

        [RESTRIÇÃO DE ESCOPO — VISÃO MACRO E BUDGETING MENTAL]
        1. PROIBIDO MICRO-PLANEJAMENTO ABSOLUTO: NUNCA cite nomes de exercícios específicos (ex: Back Squat, Snatch, Corrida 5km, etc), distâncias, séries (sets), repetições ou tempos.
        2. FOCO ESTREITO NA INTENÇÃO: O 'focoPrincipal' DEVE ser genérico, indicando apenas grupos musculares ou padrões de movimento (Ex: "Potência de Membros Inferiores + Resistência Cardiorrespiratória").

        [MAPA EXATO DE SESSÕES DO ATLETA]
        O atleta possui EXATAMENTE ${totalSessoesConfiguradas} sessões na semana, distribuídas da seguinte forma:
${mapaTexto}

        [OBRIGAÇÃO MATEMÁTICA DE VOLUME]
        1. O array visaoSemanal que você vai gerar DEVE preencher rigorosamente os treinos para as sessões configuradas.
        2. É PROIBIDO suprimir os treinos e escrever "Descanso" como \`focoPrincipal\` para as sessões listadas acima, independente de lesão ou fadiga (adapte o treino se necessário, mas mantenha-o ativo).
        3. Para os dias onde o atleta não tem sessão, gere um \`session_type\` de "Descanso".

        [LISTA OBRIGATÓRIA DE ENTRADAS — GERE EXATAMENTE ESTAS]
        O array visaoSemanal DEVE conter pelo menos uma entrada para cada linha abaixo.
        Datas que aparecem N vezes precisam de N objetos separados com valores de "session" diferentes:
        ${requiredEntriesList}

        [SESSÕES CONFIGURADAS — CONTRATOS IMUTÁVEIS DO ATLETA]
        As configurações abaixo são CONTRATOS do atleta:
        - O Local é uma RESTRIÇÃO DE INFRAESTRUTURA obrigatória: o session_type e o focoPrincipal devem ser compatíveis com o(s) local(is) disponível(is).
        - As Notas são RESTRIÇÕES ABSOLUTAS DE DESIGN: descrevem limitações físicas, preferências e restrições que NÃO PODEM ser ignoradas.
        - OBRIGAÇÃO DE TREINO: Para os dias que aparecem na lista abaixo, você DEVE gerar um "session_type" de treino ativo (ex: Força, Metcon, etc) e NÃO de Descanso. Se o atleta estiver lesionado ou fatigado, prescreva "Prehab", "Mobilidade" ou adapte os grupamentos musculares, mas NUNCA prescreva "Descanso" para as sessões contratuais abaixo.
        - DIAS NÃO CONFIGURADOS SÃO DESCANSO TOTAL: Os dias que NÃO aparecem abaixo não precisam de sessões geradas, mas caso gere algo para eles, deve ser "Descanso".
        ${formatTrainingSessions(sessions)}

        [BLOCO ATUAL DO MESOCICLO]
        - Nome: ${bloco.mesociclo} | Duração: ${duracaoSemanas} semanas

        [FORMATO — JSON]
        {
          "visaoSemanal": [
            { "date": "YYYY-MM-DD", "session": 1, "session_type": "...", "focoPrincipal": "Resumo técnico conciso aqui" }
          ]
        }
      `;

        console.log(`[gerar_calendario] Solicitando visão semanal (etapa 2/2, tentativa ${attempt}/${MAX_SEMANAL_RETRIES})...`);
        try {
          const candidato = await generateWithProvider(promptSemanal, provider, llmModel, genAI, 'gerar_calendario_semanal', 8000, 0.2);
          const calValidation = validateVisaoSemanal(candidato.visaoSemanal || [], sessions, dataInicio, duracaoSemanas);

          if (!calValidation.valid) {
            if (attempt < MAX_SEMANAL_RETRIES) {
              const preview = calValidation.errors.slice(0, 6).join('\n');
              const extra = calValidation.errors.length > 6 ? `\n...e mais ${calValidation.errors.length - 6} erros` : '';
              console.warn(`[gerar_calendario] Tentativa ${attempt}/${MAX_SEMANAL_RETRIES} — sessões omitidas:\n${preview}${extra}`);
              continue;
            }
            throw new Error(`[gerar_calendario] Sessões omitidas após ${MAX_SEMANAL_RETRIES} tentativas:\n${calValidation.errors.join('\n')}`);
          }

          resultSemanal = candidato;
          console.log(`[gerar_calendario] Visão semanal válida na tentativa ${attempt}.`);
          break;
        } catch (err: any) {
          if (attempt < MAX_SEMANAL_RETRIES) {
            console.warn(`[gerar_calendario] Erro na tentativa ${attempt}/${MAX_SEMANAL_RETRIES}: ${err.message?.substring(0, 200)}`);
            continue;
          }
          throw err;
        }
      }

      const result = {
        visaoGeralCiclo: resultGeral.visaoGeralCiclo,
        resumoMesociclo: resultGeral.resumoMesociclo,
        visaoSemanal: resultSemanal.visaoSemanal
      };

      if (result.visaoSemanal && Array.isArray(result.visaoSemanal)) {
        const totalDias = duracaoSemanas * 7;
        const startD = new Date(dataInicio + 'T12:00:00Z');

        // Mapa de dias: simplificado para conter apenas a primeira palavra minúscula (seg, ter, qua...)
        const daysWithSessions = new Set<string>();
        for (const s of sessions) {
          for (const schedDay of (s.schedule || [])) {
            const dStr = String(schedDay).toLowerCase();
            if (dStr.includes('seg')) daysWithSessions.add('segunda-feira');
            if (dStr.includes('ter')) daysWithSessions.add('terça-feira');
            if (dStr.includes('qua')) daysWithSessions.add('quarta-feira');
            if (dStr.includes('qui')) daysWithSessions.add('quinta-feira');
            if (dStr.includes('sex')) daysWithSessions.add('sexta-feira');
            if (dStr.includes('sab')) daysWithSessions.add('sábado');
            if (dStr.includes('dom')) daysWithSessions.add('domingo');
          }
        }

        console.log(`[DEBUG] Dias Ativos Detectados:`, Array.from(daysWithSessions));

        const mapDiasAtivos = new Map();
        result.visaoSemanal.forEach((dia: any) => {
          if (!mapDiasAtivos.has(dia.date)) mapDiasAtivos.set(dia.date, []);
          mapDiasAtivos.get(dia.date).push(dia);
        });

        const diasSemana = ["Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado"];
        const visaoCompleta = [];
        for (let i = 0; i < totalDias; i++) {
          const d = new Date(startD.getTime() + i * 24 * 60 * 60 * 1000);
          const dateStr = d.toISOString().split('T')[0];
          const dayName = diasSemana[d.getUTCDay()].toLowerCase();
          const weekNum = Math.floor(i / 7) + 1;
          const dayHasSessions = daysWithSessions.has(dayName);

          if (mapDiasAtivos.has(dateStr)) {
            mapDiasAtivos.get(dateStr).forEach((diaObj: any) => {
              const isRestType = diaObj.session_type === "Descanso" || diaObj.session_type === "Recuperação Ativa";
              const forceRest = !dayHasSessions;
              const rawFoco = (diaObj.focoPrincipal || diaObj.workout || diaObj.treino || '');

              // Corrige inconsistências geradas pela IA
              let finalFocoText = rawFoco;
              let finalSessionType = diaObj.session_type;

              if (!forceRest && isRestType) {
                // Dia de TREINO, mas IA gerou descanso
                finalFocoText = "Sessão de treino: foco em desenvolvimento";
                finalSessionType = "Crossfit"; // Fallback para treino genérico ao invés de 'Descanso'
              } else if (forceRest && !isRestType) {
                // Dia de DESCANSO, mas IA gerou treino
                finalFocoText = "Recuperação";
                finalSessionType = "Recuperação Ativa";
              }

              visaoCompleta.push({
                ...diaObj,
                session: forceRest ? 1 : (Number(diaObj.session) || 1),
                session_type: finalSessionType,
                focoPrincipal: finalFocoText,
                day: diasSemana[d.getUTCDay()],
                mesocycle: bloco.mesociclo,
                isDescansoAtivo: forceRest || isRestType
              });
            });
          } else {
            visaoCompleta.push({
              date: dateStr, session: 1, session_type: "Descanso", focoPrincipal: "Recuperação",
              day: diasSemana[d.getUTCDay()], mesocycle: bloco.mesociclo, isDescansoAtivo: true
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
