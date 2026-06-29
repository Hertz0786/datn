"""
Quick transcription test with better audio quality.
"""
import requests
import tempfile
import os
import sys
import io

if sys.platform == "win32":
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    except Exception:
        pass

from pytubefix import YouTube

BASE_URL = "http://127.0.0.1:8001"
YOUTUBE_URL = "https://www.youtube.com/watch?v=nqJbu-wC8Pc"

yt = YouTube(YOUTUBE_URL)
print("Title:", yt.title)

# Try best audio stream
print("\nAll streams (audio/video):")
for s in yt.streams.order_by("abr").desc():
    print(f"  itag={s.itag} type={s.type} mime={s.mime_type} res={getattr(s,'resolution','?')} abr={getattr(s,'abr','?')}")

# Download highest quality audio
with tempfile.TemporaryDirectory() as tmpdir:
    # Try video with audio first
    stream = yt.streams.filter(progressive=False).order_by("abr").desc().first()
    if not stream:
        stream = yt.streams.filter(progressive=True, file_extension="mp4").order_by("resolution").desc().first()

    print(f"\nUsing stream: {stream}")
    out_path = stream.download(output_path=tmpdir, filename="test_video")
    print("Downloaded:", os.path.getsize(out_path) / 1024, "KB")

    # Try language=en
    print("\n--- Test with language=en ---")
    with open(out_path, "rb") as f:
        files = {"file": ("test.mp4", f, "video/mp4")}
        data = {"language": "en"}
        r = requests.post(f"{BASE_URL}/transcribe-moderate", files=files, data=data, timeout=60)
        print("Status:", r.status_code)
        if r.status_code == 200:
            result = r.json()
            print("Language:", result.get("language"))
            print("Text:", result.get("text"))
            mod = result.get("moderation", {})
            print("Decision:", mod.get("decision"))
            print("Score:", mod.get("unsafeScore"))
            print("Keywords:", mod.get("flaggedKeywords"))

    # Try language=None (auto)
    print("\n--- Test with language=None (auto) ---")
    with open(out_path, "rb") as f:
        files = {"file": ("test.mp4", f, "video/mp4")}
        data = {"language": None}
        r = requests.post(f"{BASE_URL}/transcribe-moderate", files=files, data=data, timeout=60)
        print("Status:", r.status_code)
        if r.status_code == 200:
            result = r.json()
            print("Language:", result.get("language"))
            print("Text:", result.get("text"))
            mod = result.get("moderation", {})
            print("Decision:", mod.get("decision"))
            print("Score:", mod.get("unsafeScore"))
            print("Keywords:", mod.get("flaggedKeywords"))
