import cv2
import mediapipe as mp
import math
import os
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
    """
    if not os.path.exists(MODEL_PATH):
        from download_utils import ensure_model_exists
        ensure_model_exists()

    import subprocess
    
    # [NOVO] Estabilização e Otimização: Forçar autorotação e redimensionar para 720p (Max)
    # Isso resolve o "vídeo deitado" do iPhone e economiza MUITA RAM no Render.
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

    # Warehouse de métricas
    metrics = {
        "min_hip_angle": 180.0,
        "min_knee_angle": 180.0,
        "max_trunk_lean": 0.0,
    }
    
    # Rastreio do Bar Path (Zero Model)
    bar_path_pts = []

    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            # Converter para o formato MediaPipe Image e RGB
            image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)
            
            # Necessário para modo VIDEO: timestamp em ms
            frame_timestamp_ms = int(cap.get(cv2.CAP_PROP_POS_MSEC))
            
            # Detectar pose
            detection_result = landmarker.detect_for_video(mp_image, frame_timestamp_ms)
            
            # Criar cópia para desenho
            annotated_image = frame.copy()

            if detection_result.pose_landmarks:
                # Pegamos a primeira pose detectada
                landmarks = detection_result.pose_landmarks[0]
                
                # Mapeamento do PoseLandmarker (Indices padrão)
                # 11: LEFT_SHOULDER, 23: LEFT_HIP, 25: LEFT_KNEE, 27: LEFT_ANKLE
                try:
                    shoulder = landmarks[11]
                    hip = landmarks[23]
                    knee = landmarks[25]
                    ankle = landmarks[27]

                    # Calculo de biomecânica
                    knee_angle = calculate_angle(hip, knee, ankle)
                    hip_angle = calculate_angle(shoulder, hip, knee)
                    
                    # Inclinação do tronco em relação à vertical
                    # Criamos um ponto virtual vertical acima do quadril
                    vertical_pt = type('Point', (object,), {'x': hip.x, 'y': hip.y - 0.5})()
                    trunk_lean = calculate_angle(shoulder, hip, vertical_pt)
                    
                    # Atualização de recordes de profundidade
                    if knee_angle < metrics["min_knee_angle"]:
                        metrics["min_knee_angle"] = knee_angle
                    if hip_angle < metrics["min_hip_angle"]:
                        metrics["min_hip_angle"] = hip_angle
                    if trunk_lean > metrics["max_trunk_lean"]:
                        metrics["max_trunk_lean"] = trunk_lean

                    # ZERO MODEL - Cálculo C_barra
                    left_wrist = landmarks[15]
                    right_wrist = landmarks[16]
                    
                    # Ponto médio em x e y
                    bar_cx = (left_wrist.x + right_wrist.x) / 2.0
                    bar_cy = (left_wrist.y + right_wrist.y) / 2.0
                    
                    # Guardar coordenada convertendo para pixels da tela original
                    bar_pt = (int(bar_cx * width), int(bar_cy * height))
                    bar_path_pts.append(bar_pt)
                    
                    # Desenho manual simples (Legacy draw_landmarks é instável com novos objetos)
                    # Desenhamos conexões básicas do Squat
                    def draw_line(p1, p2, color=(0, 255, 0)):
                        cv2.line(annotated_image, 
                                (int(p1.x * width), int(p1.y * height)), 
                                (int(p2.x * width), int(p2.y * height)), 
                                color, 3)

                    draw_line(shoulder, hip)
                    draw_line(hip, knee)
                    draw_line(knee, ankle)
                    # Desenhar nós
                    for pt in [shoulder, hip, knee, ankle]:
                        cv2.circle(annotated_image, (int(pt.x * width), int(pt.y * height)), 6, (0, 0, 255), -1)
                        
                    # Printar Centro da Barra
                    cv2.circle(annotated_image, bar_pt, 8, (255, 255, 0), -1)
                    
                    # Desenhar Bar Path acumulado
                    for i in range(1, len(bar_path_pts)):
                        cv2.line(annotated_image, bar_path_pts[i - 1], bar_path_pts[i], (255, 255, 0), 2)
                
                except IndexError:
                    pass

            out.write(annotated_image)

    cap.release()
    out.release()
    
    # Conversão rigorosa para H.264 para ser compatível com App Flutter (Mobile/Windows)
    # [MEMORIA] Restrições de ram usando preset e threads=1
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", temp_output, "-vcodec", "libx264", "-preset", "ultrafast", "-threads", "1", "-pix_fmt", "yuv420p", output_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.exists(temp_output):
        os.remove(temp_output)
    if os.path.exists(standardized_path):
        os.remove(standardized_path)
    
    # Arredondar métricas para o LLM
    return {k: round(v, 2) for k, v in metrics.items()}
