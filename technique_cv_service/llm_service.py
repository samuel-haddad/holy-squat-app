import os
import json
import re
import requests
import google.generativeai as genai
from typing import List, Dict, Any

# CHAVE PRINCIPAL DE CONTROLE EXECUTIVO
ACTIVE_PROVIDER = "google" # Altere para "anthropic" quando quiser usar o Claude

# Inicializa as variaveis do ambiente
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

# Configuração do System Prompt de Alta Performance (CF-L4)
SYSTEM_PROMPT = """
Atue como um Head Coach CrossFit Nível 4 (CF-L4) especializado em Biomecânica de LPO e Ginásticos.
Sua análise deve ser cirúrgica, focada em EFICIÊNCIA técnica e SEGURANÇA sob carga.

Você receberá métricas dinâmicas extraídas de Visão Computacional:
- early_arm_bend (Booleano): Se True, o atleta flexionou os braços antes de completar a extensão do quadril (roubou força).
- max_bar_x_delta (Float): Desvio horizontal da barra em percentual da tela. Ideal é o mais vertical possível (Bar Path).
- catch_asymmetry (Float): Diferença de graus entre o joelho direito e esquerdo na recepção (agachamento).
- triple_extension (Booleano): Se True, atingiu boa extensão de quadril na finalização da puxada.
- min_knee_angle (Float): Profundidade máxima atingida. Abaixo de 90 indica quebra da paralela.

DIRETRIZES:
1. Faça um diagnóstico baseado *exclusivamente* nessas métricas. Mencione as fases (saída, puxada, recepção).
2. Seja encorajador, porém estrito. Se early_arm_bend for True, corrija imediatamente a puxada.
3. Se houver assimetria > 10°, alerte sobre o risco de lesões e instabilidade.
4. Liste exatamente 3 exercícios educativos (drills) ou acessórios baseados nos defeitos (ou focados em força base, caso a técnica esteja perfeita).

Retorne SEMPRE em formato JSON com esta estrutura estrita:
{
  "resume_text": "Análise técnica em texto corrido (máximo 4 frases)",
  "improve_exercises": [
     {"name": "Nome do exercício 1", "reason": "Motivo direto 1"},
     {"name": "Nome do exercício 2", "reason": "Motivo direto 2"},
     {"name": "Nome do exercício 3", "reason": "Motivo direto 3"}
  ]
}
"""

def _clean_json_response(text: str) -> str:
    """Remove blocos de código markdown do JSON retornado pela IA."""
    if text.startswith('`' * 3):
        text = re.sub(r'^`{3}(?:json)?\s*', '', text)
        text = re.sub(r'\s*`{3}$', '', text)
    return text.strip()

def generate_technique_feedback(supabase_client, exercise_name: str, metrics: Dict[str, Any]) -> Dict[str, Any]:
    """
    Recebe os dados biomecânicos dinâmicos e pede avaliação ao LLM.
    Caso a API da IA falhe, aciona um Fallback Inteligente baseado em heurística.
    """
    
    # 1. Busca o llm_model dinâmico na tabela ai_coach
    llm_model = "gemini-pro"
    try:
        res = supabase_client.table("ai_coach").select("llm_model").eq("provider", ACTIVE_PROVIDER).limit(1).execute()
        if res.data and len(res.data) > 0:
            llm_model = res.data[0]["llm_model"]
            print(f"Coach detectado no Supabase para provedor '{ACTIVE_PROVIDER}': Model={llm_model}")
    except Exception as e:
        print(f"Erro ao buscar coach na tabela ai_coach, usando padrão: {e}")

    prompt = f"O atleta executou: {exercise_name}.\nMétricas calculadas: {json.dumps(metrics, indent=2)}\nAnalise o rastro da barra, simetria e o timing de extensão. Gere o JSON técnico."

    # 2. Executa a geração de IA
    try:
        if ACTIVE_PROVIDER == "google":
            if not GEMINI_API_KEY:
                raise ValueError("GEMINI_API_KEY missing")
            
            model = genai.GenerativeModel(
                model_name=llm_model, 
                system_instruction=SYSTEM_PROMPT,
                generation_config={"response_mime_type": "application/json"}
            )
            response = model.generate_content(prompt)
            return json.loads(_clean_json_response(response.text))

        elif ACTIVE_PROVIDER == "anthropic":
            if not ANTHROPIC_API_KEY:
                raise ValueError("ANTHROPIC_API_KEY missing")
                
            headers = {
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            }
            body = {
                "model": llm_model,
                "max_tokens": 1024,
                "system": SYSTEM_PROMPT,
                "messages": [{"role": "user", "content": prompt}]
            }
            resp = requests.post("https://api.anthropic.com/v1/messages", headers=headers, json=body)
            resp.raise_for_status()
            data = resp.json()
            return json.loads(_clean_json_response(data['content'][0]['text']))

    except Exception as e:
        print(f"Erro crítico no provedor '{ACTIVE_PROVIDER}': {e}. Acionando Fallback Heurístico.")
        return _generate_fallback_mock(exercise_name, metrics)

    return _generate_fallback_mock(exercise_name, metrics)

def _generate_fallback_mock(exercise_name: str, metrics: Dict[str, Any]) -> Dict[str, Any]:
    """
    Motor Heurístico Offline (Fallback):
    Garante que o app nunca falhe, gerando um feedback determinístico baseado nas métricas extraídas 
    pelo cv_engine caso os provedores de IA estejam fora do ar.
    """
    resume = f"Feedback gerado offline pelo motor biomecânico para o seu {exercise_name}. "
    exercises = []
    
    # Análise de Early Arm Bend
    if metrics.get('early_arm_bend', False):
        resume += "Foi detectada uma puxada antecipada (braços flexionando antes da extensão total de quadril), o que reduz a potência do movimento. "
        exercises.append({"name": "Puxada Alta (High Pull)", "reason": "Ensina a paciência na segunda puxada, mantendo os braços esticados até o contato."})
    else:
        resume += "Ótima paciência na puxada, mantendo os braços conectados. "
        
    # Análise de Assimetria
    if metrics.get('catch_asymmetry', 0.0) > 10.0:
        resume += "Atenção: Houve um desequilíbrio na recepção (assimetria nos joelhos), cuidado com a estabilidade para evitar lesões. "
        exercises.append({"name": "Pistol Squats / Split Squats", "reason": "Corrige assimetrias de força e mobilidade entre as pernas."})
        
    # Análise de Profundidade
    if metrics.get('min_knee_angle', 100) < 90:
        resume += "Você atingiu excelente profundidade na quebra da paralela. "
    else:
        resume += "Faltou quebrar a paralela na recepção para maior segurança sob cargas altas. "
        exercises.append({"name": "Tempo Front Squats", "reason": "Ajuda a ganhar conforto e força no ponto mais baixo do agachamento."})

    # Preenche com exercícios padrões de base se o atleta foi perfeito e não ativou as correções acima
    if len(exercises) < 3:
        exercises.append({"name": "Snatch/Clean Balance", "reason": "Melhora a velocidade e confiança na entrada rápida sob a barra."})
    if len(exercises) < 3:
        exercises.append({"name": "Muscle Snatch / Clean", "reason": "Reforça a trajetória vertical (Bar Path) e o giro de cotovelos."})
        
    # Garante que sempre envie exatamente 3 exercicios formatados
    return {
        "resume_text": resume.strip(),
        "improve_exercises": exercises[:3]
    }