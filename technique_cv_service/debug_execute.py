from main import process_video_task, VideoProcessPayload
import sys

payload = VideoProcessPayload(
    feedback_id="7bfd2e97-a0a4-47b3-83ce-16797652f598",
    user_id="a27d07ca-d151-457f-a00a-0c424b60492d",
    exercise_name="Snatch",
    raw_video_path="raw/a27d07ca-d151-457f-a00a-0c424b60492d/1776267846650_technique.mp4"
)

try:
    process_video_task(payload)
except Exception as e:
    print("FATAL ERROR:")
    import traceback
    traceback.print_exc()
