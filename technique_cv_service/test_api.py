import requests

url = "http://127.0.0.1:8000/process-video"
payload = {
    "feedback_id": "b903cf44-fa3d-4c3e-8cfa-5df18cdd7ea1",
    "user_id": "a27d07ca-d151-457f-a00a-0c424b60492d",
    "exercise_name": "Snatch",
    "raw_video_path": "raw/a27d07ca-d151-457f-a00a-0c424b60492d/1776265126784_technique.mp4"
}

try:
    res = requests.post(url, json=payload)
    print("Status:", res.status_code)
    print("Response:", res.text)
except Exception as e:
    print("Error:", e)
