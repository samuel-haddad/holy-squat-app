import os
import requests

MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/1/pose_landmarker_heavy.task"
MODEL_PATH = "pose_landmarker_heavy.task"

def ensure_model_exists():
    """
    Downloads the model file from Google's CDN if it doesn't exist locally.
    """
    if os.path.exists(MODEL_PATH):
        print(f"Model already exists at {MODEL_PATH}")
        return

    print(f"Downloading MediaPipe Pose Heavy Model from {MODEL_URL}...")
    try:
        response = requests.get(MODEL_URL, stream=True)
        response.raise_for_status()
        
        with open(MODEL_PATH, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print("Download complete.")
    except Exception as e:
        print(f"Error downloading model: {e}")
        # If download fails, the app will likely fail too, but we report it.
        raise

if __name__ == "__main__":
    ensure_model_exists()
