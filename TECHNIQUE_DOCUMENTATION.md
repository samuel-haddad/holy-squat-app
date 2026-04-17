# Arquitetura Técnica: Feature Technique

Esta feature é um ecossistema que une **Flutter**, **Supabase** e um **Microserviço Python** especializado em Visão Computacional (CV) e Inteligência Artificial (IA).

## 1. Mapa de Arquivos

### 📱 Flutter App (Frontend)
- **lib/screens/technique/technique_list_screen.dart**: Tela de histórico ("My Library"). Gerencia a listagem de análises concluídas.
- **lib/screens/technique/technique_upload_screen.dart**: Fluxo de captura/seleção de vídeo. Utiliza `ImagePicker` com suporte nativo a `XFile` para evitar bloqueios de sandbox do iOS.
- **lib/screens/technique/technique_analysis_screen.dart**: Visualizador do resultado, integrando o player de vídeo com o feedback textual do Coach.
- **lib/services/supabase_service.dart**: Ponte de dados. Funções principais:
  - `uploadTechniqueVideo`: Envia bytes puros para o Storage via `uploadBinary`.
  - `requestTechniqueAnalysis`: Insere o trigger no banco de dados.
  - `getAllTechniqueFeedbacks`: Recupera o histórico do usuário.

### 🐍 Microserviço Python (Backend / Render)
- **technique_cv_service/main.py**: Orquestrador FastAPI. Recebe o Webhook do Supabase e gerencia a fila de execução.
- **technique_cv_service/cv_engine.py**: O "Cérebro" Biomecânico.
  - **Função Principal**: `process_video_with_mediapipe`.
  - **Fluxo**: Pré-processamento FFmpeg (720p + rotação) -> MediaPipe (extração de nós) -> Heurística "Zero Model" (Bar Path) -> Desenho sobre o vídeo.
- **technique_cv_service/llm_service.py**: Especialista em IA. Consulta a tabela `public.ai_coach` para saber qual modelo usar e gera o feedback técnico baseado nas métricas extraídas pela engine.

---

## 2. Fluxo de Dados (Step-by-Step)

1.  **App -> Storage**: O usuário sobe o vídeo bruto.
2.  **App -> DB**: O registro é criado com status `processing`.
3.  **DB -> Render**: Um Webhook avisa o microserviço Python que há trabalho.
4.  **Render -> Storage**: O Python baixa o vídeo.
5.  **Processamento CV**: O FFmpeg normaliza a rotação e reduz para 720p para economizar RAM. O MediaPipe extrai ângulos e o rastro da barra (ponto médio dos pulsos).
6.  **IA Coach**: O LLM (Gemini/Claude) gera o feedback baseado nos ângulos coletados.
7.  **Render -> Storage**: O vídeo com os desenhos dos ossos e trajetória da barra é enviado de volta.
8.  **Render -> DB**: O registro é atualizado para `completed` com o vídeo final e o feedback textual.
9.  **App**: O usuário vê o resultado final.

---

## 3. Estruturação das Funções Principais

### No Backend (CV Engine)
A função `process_video_with_mediapipe` é o coração do sistema:
- **Normalização**: Usa FFmpeg para garantir que o vídeo esteja em pé.
- **Tracking**: Varre o vídeo frame a frame extraindo as coordenadas 3D.
- **Heurística Zero Model**: Calcula o rastro da barra pelo ponto médio dos pulsos (Índices 15 e 16).

---

## 4. Banco de Dados
A tabela central é a `public.technique_feedbacks`.
- **Primary Key**: `user_id` + `exercise_name` (Mantém apenas a análise mais recente de cada movimento).
- **Relacionamento**: Usa o `user_id` para vincular ao perfil do atleta.
