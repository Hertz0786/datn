"""
Test speech-to-text moderation on a YouTube video.
Usage: python test_stt_youtube.py
"""
import sys
import os
import io

# Fix Windows console Unicode encoding
if sys.platform == "win32":
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
    except Exception:
        pass
import sys
import os
import time
import tempfile
import requests

BASE_URL = "http://127.0.0.1:8001"
YOUTUBE_URL = "https://www.youtube.com/watch?v=nqJbu-wC8Pc"


def test_health():
    r = requests.get(f"{BASE_URL}/health", timeout=5)
    print(f"Health: {r.status_code}")
    data = r.json()
    print(f"  modelLoaded: {data.get('modelLoaded')}")
    print(f"  whisperLoaded: {data.get('whisperLoaded')}")
    return data.get("whisperLoaded", False)


def on_progress_clean(stream, chunk, bytes_remaining):
    total = stream.filesize
    received = total - bytes_remaining
    pct = (received / total * 100) if total else 0
    print(f"\r  Downloading... {pct:.1f}% ({received//1024}KB / {total//1024}KB)", end="", flush=True)


def download_youtube_video(url, output_path):
    """Download YouTube video using pytubefix."""
    from pytubefix import YouTube

    print(f"\nDownloading: {url}")
    yt = YouTube(url, on_progress_callback=on_progress_clean)
    print(f"  Title: {yt.title}")
    print(f"  Duration: {yt.length}s")

    stream = yt.streams.filter(progressive=True, file_extension='mp4').order_by('resolution').asc().first()
    if not stream:
        stream = yt.streams.filter(progressive=True).order_by('resolution').first()
    if not stream:
        stream = yt.streams.order_by('resolution').first()

    print(f"  Stream: {stream}")
    ext = stream.subtype or 'mp4'
    out_file = stream.download(output_path=output_path, filename="test_video")
    print()
    # pytubefix may not preserve extension in filename; rename to include it
    raw_path = out_file
    final_path = os.path.join(output_path, f"test_video.{ext}")
    if raw_path != final_path and os.path.exists(raw_path):
        os.replace(raw_path, final_path)
    elif not os.path.exists(final_path):
        for candidate in [f"test_video.{ext}", "test_video.mp4"]:
            candidate_path = os.path.join(output_path, candidate)
            if os.path.exists(candidate_path):
                final_path = candidate_path
                break
    print(f"  Saved to: {final_path}")
    return final_path


def moderate_video_frames(file_path):
    """Send video to /moderate endpoint (frame analysis)."""
    print(f"\n{'='*50}")
    print("TEST 1: Frame Moderation (/moderate)")
    print(f"{'='*50}")
    print(f"File: {file_path}")
    print(f"Size: {os.path.getsize(file_path) / 1024 / 1024:.2f} MB")

    with open(file_path, 'rb') as f:
        files = {'file': (os.path.basename(file_path), f, 'video/mp4')}
        start = time.time()
        r = requests.post(f"{BASE_URL}/moderate", files=files, timeout=60)
        elapsed = time.time() - start

    print(f"\nStatus: {r.status_code} | Time: {elapsed:.1f}s")
    result = r.json()
    print(f"  Decision:      {result.get('decision', 'N/A')}")
    print(f"  Frames checked: {result.get('framesChecked', 'N/A')}")
    print(f"  Unsafe score:   {result.get('unsafeScore', 'N/A')}")
    print(f"  Unsafe label:  {result.get('unsafeLabel', 'N/A')}")
    print(f"  Top label:     {result.get('topLabel', 'N/A')}")
    return result


def transcribe_and_moderate(file_path):
    """Send video to /transcribe-moderate endpoint."""
    print(f"\n{'='*50}")
    print("TEST 2: Speech Transcription + Moderation (/transcribe-moderate)")
    print(f"{'='*50}")
    print(f"File: {file_path}")
    print(f"Size: {os.path.getsize(file_path) / 1024 / 1024:.2f} MB")

    with open(file_path, 'rb') as f:
        files = {'file': (os.path.basename(file_path), f, 'video/mp4')}
        data = {'language': 'vi'}
        start = time.time()
        r = requests.post(f"{BASE_URL}/transcribe-moderate", files=files, data=data, timeout=180)
        elapsed = time.time() - start

    print(f"\nStatus: {r.status_code} | Time: {elapsed:.1f}s")
    result = r.json()

    print(f"\n  [Transcription]")
    print(f"  Language: {result.get('language', 'N/A')}")
    text = result.get('text', '')
    print(f"  Text: {text if text else '(empty / no speech detected)'}")

    mod = result.get('moderation', {})
    print(f"\n  [Speech Moderation]")
    print(f"  Decision:        {mod.get('decision', 'N/A')}")
    print(f"  Unsafe Score:    {mod.get('unsafeScore', 'N/A')}")
    print(f"  Flagged Keywords: {mod.get('flaggedKeywords', [])}")
    print(f"  Is Flagged:      {mod.get('isFlagged', False)}")

    return result


if __name__ == "__main__":
    print("=" * 60)
    print("STT Speech-to-Text Moderation Test")
    print("Target URL:", YOUTUBE_URL)
    print("=" * 60)

    # 1. Health check
    if not test_health():
        print("ERROR: Whisper model not loaded!")
        sys.exit(1)

    # 2. Download video
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"Temp dir: {tmpdir}")

        video_path = download_youtube_video(YOUTUBE_URL, tmpdir)
        if not video_path or not os.path.exists(video_path):
            print("Download failed!")
            sys.exit(1)

        # 3. Test frame moderation
        moderate_video_frames(video_path)

        # 4. Test transcription + moderation
        result = transcribe_and_moderate(video_path)

    print("\n" + "=" * 60)
    mod = result.get('moderation', {})
    decision = mod.get('decision', 'N/A')
    score = mod.get('unsafeScore', 'N/A')
    keywords = mod.get('flaggedKeywords', [])
    print(f"OVERALL SPEECH MODERATION RESULT:")
    print(f"  Decision: {decision}  |  Score: {score}")
    if keywords:
        print(f"  Detected keywords: {keywords}")
    print("=" * 60)
