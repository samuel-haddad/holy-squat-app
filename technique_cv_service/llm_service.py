import os
import json
import google.generativeai as genai
from pydantic import BaseModel, ConfigDict
from typing import List, Dict, Any

# Inicializa as variaveis do ambiente
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY)

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

def generate_technique_feedback(exercise_name: str, metrics: Dict[str, Any]) -> Dict[str, Any]:
    """
    Recebe os dados brutos e pede uma avaliação biomecânica para a LLM.
    Retorna o dicionário parseado do JSON do Gemini ou um dicionário genérico de fallback em caso de erro/falta de chave.
    """
    if not GEMINI_API_KEY:
        print("Warning: GEMINI_API_KEY not provided. Returning fallback metrics-only message.")
        return _generate_fallback_mock(exercise_name, metrics)
        
    prompt = f"O atleta executou: {exercise_name}.\nMétricas calculadas pela Visão Computacional: {json.dumps(metrics, indent=2)}\nAnalise e gere o JSON técnico de acordo com as diretrizes."

    model = genai.GenerativeModel(
        model_name="gemini-pro", 
        system_instruction=SYSTEM_PROMPT,
        generation_config={
            "response_mime_type": "application/json"
        }
    )

    try:
        response = model.generate_content(prompt)
        # Tenta decodificar a resposta JSON estrita do modelo
        feedback_data = json.loads(response.text)
        return feedback_data
    except Exception as e:
        print(f"Error calling Gemini: {e}")
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
