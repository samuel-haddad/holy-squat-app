import cv2
import mediapipe as mp
import math
import os
import numpy as np
import subprocess
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Modelo baixado anteriormente
MODEL_PATH = "pose_landmarker_lite.task"

def calculate_angle(a, b, c):
    """
    Calcula o ângulo entre 3 pontos (a, b, c) onde b é o vértice.
    Points are objects with x and y attributes.
    """
    radians = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x)
    angle = abs(radians * 180.0 / math.pi)
    if angle > 180.0:
        angle = 360 - angle
    return angle

def process_video_with_mediapipe(input_path: str, output_path: str):
    """
    Roda a extração do Pose Estimation usando a moderna MediaPipe Tasks API.
    Utiliza análise de Série Temporal para métricas dinâmicas.
    """
    if not os.path.exists(MODEL_PATH):
        from download_utils import ensure_model_exists
        ensure_model_exists()
    
    # 1. Estabilização e Otimização: Forçar autorotação e redimensionar para 720p (Max)
    standardized_path = input_path + "_std.mp4"
    result = subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", input_path,
        "-vf", "scale='if(gt(a,1),-1,720)':'if(gt(a,1),720,-1)',format=yuv420p",
        "-c:v", "libx264", "-preset", "ultrafast", "-threads", "1",
        standardized_path
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"⚠️ FFmpeg Error on stabilization:\n{result.stderr}")
    
    # Se o FFmpeg falhou (ou gerou arquivo vazio), tentamos usar o original como fallback
    if os.path.exists(standardized_path) and os.path.getsize(standardized_path) > 0:
        working_path = standardized_path
    else:
        print(f"⚠️ Fallback to original input: {input_path}")
        working_path = input_path

    cap = cv2.VideoCapture(working_path)
    if not cap.isOpened():
        raise Exception(f"Failed to open video file: {working_path}. FFmpeg err: {result.stderr}")
        
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)

    # VideoWriter setup - Inicializamos num wrapper mp4 basico primeiro
    temp_output = output_path + "_raw.mp4"
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(temp_output, fourcc, fps, (width, height))

    # Configuração do Pose Landmarker
    base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
    options = vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO
    )

    # [BIO] Função de Suavização (Média Móvel) para evitar tremida no gráfico/ossos
    def smooth_array(arr, window=5):
        if len(arr) < window: return arr
        return np.convolve(arr, np.ones(window)/window, mode='same').tolist()

    # [VIS] Helper para desenhar o esqueleto técnico
    def draw_skeleton(image, lms, w, h, color_primary=(0, 255, 0), color_secondary=(0, 0, 255)):
        connections = [
            (11, 12), (11, 23), (12, 24), (23, 24), # Tronco (Caixa)
            (11, 13), (13, 15), (12, 14), (14, 16), # Braços
            (23, 25), (25, 27), (24, 26), (26, 28)  # Pernas
        ]
        for start_idx, end_idx in connections:
            p1, p2 = lms[start_idx], lms[end_idx]
            cv2.line(image, (int(p1.x * w), int(p1.y * h)), (int(p2.x * w), int(p2.y * h)), color_primary, 2)
        
        # Desenha os nós (Articulações)
        for idx in [11,12,13,14,15,16,23,24,25,26,27,28]:
            p = lms[idx]
            cv2.circle(image, (int(p.x * w), int(p.y * h)), 5, color_secondary, -1)

    # [DATA] Inicialização dos buffers de métricas (Séres Temporais)
    history = {
        "ts": [], "l_knee": [], "r_knee": [], "l_hip": [], "l_elbow": [],
        "bar_x": [], "bar_y": []
    }
    bar_path_pts = []

    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            frame_timestamp_ms = int(cap.get(cv2.CAP_PROP_POS_MSEC))
            image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)
            
            detection_result = landmarker.detect_for_video(mp_image, frame_timestamp_ms)
            annotated_image = frame.copy()

            if detection_result.pose_landmarks:
                landmarks = detection_result.pose_landmarks[0]
                
                try:
                    # Mapeamento Bilateral
                    lw, rw = landmarks[15], landmarks[16] # Pulsos
                    lh, rh = landmarks[23], landmarks[24] # Quadril
                    lk, rk = landmarks[25], landmarks[26] # Joelhos
                    ls, rs = landmarks[11], landmarks[12] # Ombros

                    # Cálculos de Ângulos (Lado Esquerdo como referência padrão)
                    lk_ang = calculate_angle(lh, lk, landmarks[27])
                    rk_ang = calculate_angle(rh, rk, landmarks[28])
                    lh_ang = calculate_angle(ls, lh, lk)
                    le_ang = calculate_angle(ls, landmarks[13], lw)

                    # ZERO MODEL - Posição da Barra
                    bar_cx = (lw.x + rw.x) / 2.0
                    bar_cy = (lw.y + rw.y) / 2.0
                    bar_pt = (int(bar_cx * width), int(bar_cy * height))
                    bar_path_pts.append(bar_pt)
                    
                    # Store Metrics for history
                    history["ts"].append(frame_timestamp_ms)
                    history["l_knee"].append(lk_ang)
                    history["r_knee"].append(rk_ang)
                    history["l_hip"].append(lh_ang)
                    history["l_elbow"].append(le_ang)
                    history["bar_x"].append(bar_cx)
                    history["bar_y"].append(bar_cy)
                    
                    # Desenho Técnico Avançado
                    draw_skeleton(annotated_image, landmarks, width, height)
                    
                    # Printar Centro da Barra e Path (Em Cyan)
                    cv2.circle(annotated_image, bar_pt, 8, (255, 255, 0), -1)
                    for i in range(1, len(bar_path_pts)):
                        cv2.line(annotated_image, bar_path_pts[i - 1], bar_path_pts[i], (255, 255, 0), 2)
                
                except (IndexError, AttributeError):
                    pass

            out.write(annotated_image)

    cap.release()
    out.release()
    
    # --- ANÁLISE BIOMECÂNICA PÓS-VÍDEO (COM SUAVIZAÇÃO) ---
    metrics = {
        "max_bar_x_delta": 0.0, 
        "early_arm_bend": False, 
        "triple_extension": False, 
        "catch_asymmetry": 0.0,
        "min_knee_angle": 180.0
    }
    
    if len(history["ts"]) > 10:
        # Suavização das curvas para análise de tendência
        smooth_knee = smooth_array(history["l_knee"])
        smooth_hip = smooth_array(history["l_hip"])
        smooth_elbow = smooth_array(history["l_elbow"])
        
        # 1. Deslocamento Horizontal da Barra
        metrics["max_bar_x_delta"] = round((max(history["bar_x"]) - min(history["bar_x"])) * 100, 2)
        
        # 2. Early Arm Bend (Window analysis)
        max_hip_idx = np.argmax(smooth_hip)
        # Olhamos uma janela de 5 frames antes da extensão máxima do quadril
        window_elbow = smooth_elbow[max(0, max_hip_idx-5):max_hip_idx]
        if window_elbow and min(window_elbow) < 160: 
            metrics["early_arm_bend"] = True
            
        # 3. Triple Extension
        if smooth_hip[max_hip_idx] > 168.0:
            metrics["triple_extension"] = True
        
        # 4. Profundidade e Assimetria
        min_knee_idx = np.argmin(smooth_knee)
        metrics["catch_asymmetry"] = round(abs(history["l_knee"][min_knee_idx] - history["r_knee"][min_knee_idx]), 2)
        metrics["min_knee_angle"] = round(smooth_knee[min_knee_idx], 2)

    # --- PROTEÇÃO E COMPRESSÃO (FFMPEG FINAL) ---
    # Conversão rigorosa para H.264 para ser compatível com App Flutter (Mobile/Windows)
    # [MEMORIA] Restrições de ram usando preset e threads=1
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", temp_output, 
        "-vcodec", "libx264", "-preset", "ultrafast", "-threads", "1", 
        "-pix_fmt", "yuv420p", output_path
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Cleanup crítico de arquivos temporários
    if os.path.exists(temp_output):
        os.remove(temp_output)
    if os.path.exists(standardized_path):
        os.remove(standardized_path)
    
    return metrics