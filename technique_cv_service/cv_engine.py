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
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", input_path,
        "-vf", "scale='if(gt(a,1),-1,720)':'if(gt(a,1),720,-1)',format=yuv420p",
        "-c:v", "libx264", "-preset", "ultrafast", "-threads", "1",
        standardized_path
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Se o FFmpeg falhou (vídeo corrompido), tentamos usar o original como fallback
    working_path = standardized_path if os.path.exists(standardized_path) else input_path

    cap = cv2.VideoCapture(working_path)
    if not cap.isOpened():
        raise Exception(f"Failed to open video file: {working_path}")
        
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

    # Warehouse de Métricas (Séries Temporais)
    history = {
        "ts": [], "l_knee": [], "r_knee": [], "l_hip": [], "r_hip": [],
        "l_elbow": [], "r_elbow": [], "bar_x": [], "bar_y": [], "sh_y": []
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
                    ls, rs = landmarks[11], landmarks[12] # Ombros
                    le, re = landmarks[13], landmarks[14] # Cotovelos
                    lw, rw = landmarks[15], landmarks[16] # Pulsos
                    lh, rh = landmarks[23], landmarks[24] # Quadril
                    lk, rk = landmarks[25], landmarks[26] # Joelhos
                    la, ra = landmarks[27], landmarks[28] # Tornozelos

                    # Cálculos de Ângulos Bilaterais
                    lk_ang = calculate_angle(lh, lk, la)
                    rk_ang = calculate_angle(rh, rk, ra)
                    lh_ang = calculate_angle(ls, lh, lk)
                    rh_ang = calculate_angle(rs, rh, rk)
                    le_ang = calculate_angle(ls, le, lw)
                    re_ang = calculate_angle(rs, re, rw)

                    # ZERO MODEL - Posição da Barra
                    bar_cx = (lw.x + rw.x) / 2.0
                    bar_cy = (lw.y + rw.y) / 2.0
                    bar_pt = (int(bar_cx * width), int(bar_cy * height))
                    bar_path_pts.append(bar_pt)
                    
                    # Salvando no histórico do frame
                    history["ts"].append(frame_timestamp_ms)
                    history["l_knee"].append(lk_ang)
                    history["r_knee"].append(rk_ang)
                    history["l_hip"].append(lh_ang)
                    history["r_hip"].append(rh_ang)
                    history["l_elbow"].append(le_ang)
                    history["r_elbow"].append(re_ang)
                    history["bar_x"].append(bar_cx)
                    history["bar_y"].append(bar_cy)
                    history["sh_y"].append((ls.y + rs.y) / 2.0)
                    
                    # Desenho Técnico sobre o vídeo
                    def draw_line(p1, p2, color=(0, 255, 0)):
                        cv2.line(annotated_image, 
                                (int(p1.x * width), int(p1.y * height)), 
                                (int(p2.x * width), int(p2.y * height)), 
                                color, 3)

                    # Desenha esqueleto esquerdo como base
                    draw_line(ls, lh)
                    draw_line(lh, lk)
                    draw_line(lk, la)
                    draw_line(ls, le)
                    draw_line(le, lw)

                    for pt in [ls, lh, lk, la, le, lw]:
                        cv2.circle(annotated_image, (int(pt.x * width), int(pt.y * height)), 6, (0, 0, 255), -1)
                        
                    # Printar Centro da Barra e Path
                    cv2.circle(annotated_image, bar_pt, 8, (255, 255, 0), -1)
                    for i in range(1, len(bar_path_pts)):
                        cv2.line(annotated_image, bar_path_pts[i - 1], bar_path_pts[i], (255, 255, 0), 2)
                
                except IndexError:
                    pass

            out.write(annotated_image)

    cap.release()
    out.release()
    
    # --- ANÁLISE BIOMECÂNICA PÓS-VÍDEO ---
    metrics = {
        "max_bar_x_delta": 0.0, 
        "early_arm_bend": False, 
        "triple_extension": False, 
        "catch_asymmetry": 0.0,
        "min_knee_angle": 180.0
    }
    
    if history["ts"]:
        # 1. Deslocamento Horizontal da Barra (Eficiência - Loop da barra)
        metrics["max_bar_x_delta"] = round((max(history["bar_x"]) - min(history["bar_x"])) * 100, 2)
        
        # 2. Early Arm Bend (Puxada antecipada)
        max_hip_idx = np.argmax(history["l_hip"])
        pre_extension_elbow = history["l_elbow"][max(0, max_hip_idx - 10)]
        if pre_extension_elbow < 160: 
            metrics["early_arm_bend"] = True
            
        # 3. Triple Extension (Verifica se houve abertura considerável do quadril)
        if history["l_hip"][max_hip_idx] > 165.0:
            metrics["triple_extension"] = True
        
        # 4. Profundidade e Assimetria na Recepção
        min_knee_idx = np.argmin(history["l_knee"])
        metrics["catch_asymmetry"] = round(abs(history["l_knee"][min_knee_idx] - history["r_knee"][min_knee_idx]), 2)
        metrics["min_knee_angle"] = round(history["l_knee"][min_knee_idx], 2)

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