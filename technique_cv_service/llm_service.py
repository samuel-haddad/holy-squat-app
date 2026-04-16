import os
import json
import requests
import google.generativeai as genai
from typing import List, Dict, Any

# CHAVE PRINCIPAL DE CONTROLE EXCECUTIVO
ACTIVE_PROVIDER = "google" # Altere para "anthropic" quando quiser usar o Claude

# Inicializa as variaveis do ambiente
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

# Configuração do System Prompt de Educação Física
SYSTEM_PROMPT = """
Atue como um Head Coach, CF-L4, certificado pela CrossFit. 
Vou lhe passar métricas de graus extraídas de um atleta realizando um levantamento de peso (LPO) ou Powerlifting. 
Aja de forma técnica, sendo encorajador, porém estrito.

Crie um resumo curto e objetivo (no máximo 3 a 4 frases) diagnosticando o movimento baseado nas métricas computacionais, apontando se o atleta manteve estabilidade ou se há algum aspecto incorreto (valgo, pouca profundidade, inclinação de tronco excessiva, etc.).

E liste exatamente 3 exercícios acessórios/corretivos ou treinos educativos (drills) baseados no erro (ou para melhorar a força do movimento se o movimento foi bom).
Retorne SEMPRE em formato JSON com esta estrutura estrita:
{
  "resume_text": "Análise técnica em texto corrido",
  "improve_exercises": [
     {"name": "Nome do exercício de melhoria 1", "reason": "Motivo da escolha 1"},
     {"name": "Nome do exercício de melhoria 2", "reason": "Motivo da escolha 2"},
     {"name": "Nome do exercício de melhoria 3", "reason": "Motivo da escolha 3"}
  ]
}
"""

def generate_technique_feedback(supabase_client, exercise_name: str, metrics: Dict[str, Any]) -> Dict[str, Any]:
    """
    Recebe os dados brutos e pede uma avaliação biomecânica para a LLM configurada no banco (ai_coach).
    Retorna o dicionário parseado ou um dicionário de fallback.
    """
    
    # 1. Busca o llm_model dinâmico na tabela ai_coach
    llm_model = "gemini-pro"
    try:
        res = supabase_client.table("ai_coach").select("llm_model").eq("provider", ACTIVE_PROVIDER).limit(1).execute()
        if res.data and len(res.data) > 0:
            llm_model = res.data[0]["llm_model"]
            print(f"Coach detectado no Supabase para provedor '{ACTIVE_PROVIDER}': Model={llm_model}")
    except Exception as e:
        print(f"Erro ao buscar coach na tabela ai_coach, usando padrao: {e}")

    prompt = f"O atleta executou: {exercise_name}.\nMétricas calculadas pela Visão Computacional: {json.dumps(metrics, indent=2)}\nAnalise e gere o JSON técnico de acordo com as diretrizes."

    # 2. Executa a geração usando a nuvem apropriada
    if ACTIVE_PROVIDER == "google":
        if not GEMINI_API_KEY:
            print("Warning: GEMINI_API_KEY not provided.")
            return _generate_fallback_mock(exercise_name, metrics)
            
        try:
            model = genai.GenerativeModel(
                model_name=llm_model, 
                system_instruction=SYSTEM_PROMPT,
                generation_config={"response_mime_type": "application/json"}
            )
            response = model.generate_content(prompt)
            return json.loads(response.text)
        except Exception as e:
            print(f"Error calling Gemini: {e}")
            return _generate_fallback_mock(exercise_name, metrics)

    elif ACTIVE_PROVIDER == "anthropic":
        if not ANTHROPIC_API_KEY:
            print("Warning: ANTHROPIC_API_KEY not provided.")
            return _generate_fallback_mock(exercise_name, metrics)
            
        try:
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
            raw_text = data['content'][0]['text']
            
            import re
            if raw_text.startswith('```'):
                raw_text = re.sub(r'^```(?:json)?\s*', '', raw_text)
                raw_text = re.sub(r'\s*```$', '', raw_text)
                
            return json.loads(raw_text)
        except Exception as e:
            print(f"Error calling Claude: {e}")
            return _generate_fallback_mock(exercise_name, metrics)

    return _generate_fallback_mock(exercise_name, metrics)

def _generate_fallback_mock(exercise_name: str, metrics: Dict[str, Any]) -> Dict[str, Any]:
    # Mock hardcoded backup (Caso a API Key nao funcione ou de erro)
    resume = f"Feedback gerado offline para {exercise_name}. "
    if metrics.get('min_hip_angle', 100) < 90:
        resume += "Excelente profundidade atingida abaixo da paralela, padrão ouro."
    else:
        resume += "A profundidade pode ser melhorada para atingir a quebra da paralela do joelho com quadril."
        
    return {
        "resume_text": resume,
        "improve_exercises": [
            {"name": "Back Squat", "reason": "Fundamental para força bruta na cadeia posterior."},
            {"name": "Goblet Squat", "reason": "Mantém o peito erguido com maior facilidade."}
        ]
    }
