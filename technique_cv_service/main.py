from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel
import os
import time
from cv_engine import process_video_with_mediapipe
from download_utils import ensure_model_exists
from supabase import create_client, Client
from dotenv import load_dotenv

# Carregar variaveis de ambiente (.env no root ou local)
load_dotenv("../.env")

SUPABASE_URL = os.getenv("SUPABASE_URL")
# IMPORTANTE: Recomenda-se usar SERVICE_ROLE_KEY para bypass de RLS no backend
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_ANON_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

app = FastAPI(title="Technique CV Service")

@app.on_event("startup")
def startup_event():
    print("Initializing Service: Checking MediaPipe Model...")
    ensure_model_exists()

class VideoProcessPayload(BaseModel):
    feedback_id: str
    user_id: str
    exercise_name: str
    raw_video_path: str

def process_video_task(payload: VideoProcessPayload):
    """
    Ciclo completo: Download -> Processamento CV -> Upload -> DB Update
    """
    feedback_id = payload.feedback_id
    raw_path = payload.raw_video_path
    local_raw = f"temp_raw_{feedback_id}.mp4"
    local_processed = f"temp_processed_{feedback_id}.mp4"
    processed_storage_path = f"processed/{payload.user_id}/{feedback_id}.mp4"

    try:
        # 1. Download do Supabase Storage
        print(f"Downloading raw video: {raw_path}")
        with open(local_raw, 'wb+') as f:
            res = supabase.storage.from_('technique_videos').download(raw_path)
            f.write(res)

        # 2. Processamento de Visão Computacional (MediaPipe Tasks)
        print("Processing video with CV Engine...")
        metrics = process_video_with_mediapipe(local_raw, local_processed)
        print(f"Metrics: {metrics}")

        # 3. Upload do vídeo processado
        print(f"Uploading processed video to {processed_storage_path}")
        with open(local_processed, 'rb') as f:
            supabase.storage.from_('technique_videos').upload(
                path=processed_storage_path,
                file=f,
                file_options={"cache-control": "3600", "upsert": "true"}
            )
        
        # 4. Geração de Feedback (Mock LLM baseado em métricas)
        resume = f"Análise concluída para {payload.exercise_name}. "
        if metrics['min_hip_angle'] < 90:
            resume += "Excelente profundidade atingida abaixo da paralela. "
        else:
            resume += "A profundidade pode ser melhorada para atingir a paralela. "
        
        if metrics['max_trunk_lean'] > 40:
            resume += "Notamos uma inclinação excessiva do tronco à frente, cuidado com o core."
        
        improve_exercises = [
            {"name": "Goblet Squats", "reason": "Melhora a postura vertical do tronco."},
            {"name": "Box Squats", "reason": "Ajuda no controle da profundidade e estabilidade."}
        ]

        # 5. Update Final no Banco de Dados
        print("Updating database record...")
        supabase.table("technique_feedbacks").update({
            "processed_video_path": processed_storage_path,
            "resume_text": resume,
            "improve_exercises": improve_exercises,
            "status": "completed"
        }).eq("id", feedback_id).execute()

        print(f"Success! Job {feedback_id} complete.")

    except Exception as e:
        print(f"Critical error in job {feedback_id}: {e}")
        # Update status para failed
        try:
            supabase.table("technique_feedbacks").update({"status": "failed"}).eq("id", feedback_id).execute()
        except: pass
    finally:
        # Cleanup arquivos temporários
        if os.path.exists(local_raw): os.remove(local_raw)
        if os.path.exists(local_processed): os.remove(local_processed)

@app.post("/process-video")
async def process_video_endpoint(payload: VideoProcessPayload, background_tasks: BackgroundTasks):
    if not payload.raw_video_path:
        raise HTTPException(status_code=400, detail="Missing video path")
    
    background_tasks.add_task(process_video_task, payload)
    return {"status": "processing", "message": "Video job enqueued", "feedback_id": payload.feedback_id}

@app.get("/health")
def health_check():
    return {"status": "running"}
