import os
import re
import tempfile
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import tensorflow as tf
import whisper
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image, ImageOps
import logging

_logger = logging.getLogger(__name__)


BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = Path(os.getenv("AI_MODEL_PATH", BASE_DIR / "ai.h5"))
IMAGE_SIZE = int(os.getenv("AI_IMAGE_SIZE", "224"))
BLOCK_THRESHOLD = float(os.getenv("AI_BLOCK_THRESHOLD", "0.75"))
REVIEW_THRESHOLD = float(os.getenv("AI_REVIEW_THRESHOLD", "0.55"))
MAX_VIDEO_FRAMES = int(os.getenv("AI_MAX_VIDEO_FRAMES", "12"))
MAX_FILE_MB = int(os.getenv("AI_MAX_FILE_MB", "80"))
WHISPER_MODEL_SIZE = os.getenv("WHISPER_MODEL_SIZE", "base")

CLASS_NAMES = [
    "baoluc",
    "draw",
    "hentai",
    "phanbiet",
    "sex-nude",
    "wound",
]

UNSAFE_LABELS = {
    item.strip()
    for item in os.getenv(
        "AI_UNSAFE_LABELS",
        "baoluc,hentai,phanbiet,sex-nude,wound",
    ).split(",")
    if item.strip()
}

app = FastAPI(title="Kiddo AI Media Moderation", version="1.0.0")
model: Any | None = None
whisper_model: Any | None = None


@app.on_event("startup")
def load_ai_model() -> None:
    global model
    if not MODEL_PATH.exists():
        raise RuntimeError(f"AI model not found: {MODEL_PATH}")
    model = tf.keras.models.load_model(MODEL_PATH, compile=False)


@app.on_event("startup")
def load_whisper_model() -> None:
    global whisper_model
    try:
        whisper_model = whisper.load_model(WHISPER_MODEL_SIZE)
    except Exception as error:
        raise RuntimeError(
            f"Failed to load Whisper model ({WHISPER_MODEL_SIZE}): {error}"
        ) from error


def _require_model():
    if model is None:
        raise HTTPException(status_code=503, detail="AI model is not loaded.")
    return model


def _require_whisper():
    if whisper_model is None:
        raise HTTPException(status_code=503, detail="Whisper model is not loaded.")
    return whisper_model


def _preprocess_image(image: Image.Image) -> np.ndarray:
    image = ImageOps.exif_transpose(image).convert("RGB")
    image = image.resize((IMAGE_SIZE, IMAGE_SIZE))
    image_array = np.asarray(image, dtype=np.float32) / 255.0
    return np.expand_dims(image_array, axis=0)


def _predict_image(image: Image.Image) -> dict[str, Any]:
    ai_model = _require_model()
    prediction = ai_model.predict(_preprocess_image(image), verbose=0)[0]
    scores = {
        label: float(prediction[index])
        for index, label in enumerate(CLASS_NAMES)
    }
    top_label = max(scores, key=scores.get)
    unsafe_scores = {
        label: score
        for label, score in scores.items()
        if label in UNSAFE_LABELS
    }
    unsafe_label = max(unsafe_scores, key=unsafe_scores.get) if unsafe_scores else ''
    return {
        "scores": scores,
        "topLabel": top_label,
        "topScore": scores[top_label],
        "unsafeLabel": unsafe_label,
        "unsafeScore": unsafe_scores.get(unsafe_label, 0.0),
    }


def _decision_from_score(unsafe_score: float) -> str:
    if unsafe_score >= BLOCK_THRESHOLD:
        return "BLOCKED"
    if unsafe_score >= REVIEW_THRESHOLD:
        return "REVIEW"
    return "APPROVED"


def _read_image(file_bytes: bytes) -> Image.Image:
    try:
        from io import BytesIO

        return Image.open(BytesIO(file_bytes))
    except Exception as error:
        raise HTTPException(status_code=400, detail=f"Invalid image file: {error}") from error


def _sample_video_frames(video_path: str, max_frames: int) -> list[tuple[int, Image.Image]]:
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise HTTPException(status_code=400, detail="Invalid or unsupported video file.")

    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if frame_count <= 0:
        indices = list(range(max_frames))
    else:
        sample_count = max(1, min(max_frames, frame_count))
        indices = sorted(set(np.linspace(0, frame_count - 1, sample_count, dtype=int).tolist()))

    frames: list[tuple[int, Image.Image]] = []
    try:
        for frame_index in indices:
            capture.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
            ok, frame = capture.read()
            if not ok or frame is None:
                continue
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            frames.append((frame_index, Image.fromarray(rgb)))
    finally:
        capture.release()

    if not frames:
        raise HTTPException(status_code=400, detail="Could not extract frames from video.")
    return frames


def _summarize_results(results: list[dict[str, Any]], media_type: str) -> dict[str, Any]:
    if not results:
        return {
            "allowed": True,
            "decision": "APPROVED",
            "mediaType": media_type,
            "topLabel": "",
            "topScore": 0.0,
            "unsafeLabel": "",
            "unsafeScore": 0.0,
            "framesChecked": 0,
            "thresholds": {
                "review": REVIEW_THRESHOLD,
                "block": BLOCK_THRESHOLD,
            },
            "matches": [],
        }
    worst = max(results, key=lambda item: item["unsafeScore"])
    decision = _decision_from_score(worst["unsafeScore"])
    return {
        "allowed": decision == "APPROVED",
        "decision": decision,
        "mediaType": media_type,
        "topLabel": worst["topLabel"],
        "topScore": worst["topScore"],
        "unsafeLabel": worst["unsafeLabel"],
        "unsafeScore": worst["unsafeScore"],
        "framesChecked": len(results),
        "thresholds": {
            "review": REVIEW_THRESHOLD,
            "block": BLOCK_THRESHOLD,
        },
        "matches": [
            {
                "frameIndex": item.get("frameIndex"),
                "unsafeLabel": item["unsafeLabel"],
                "unsafeScore": item["unsafeScore"],
                "topLabel": item["topLabel"],
                "topScore": item["topScore"],
            }
            for item in results
            if item["unsafeScore"] >= REVIEW_THRESHOLD
        ][:20],
    }


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "modelLoaded": model is not None,
        "whisperLoaded": whisper_model is not None,
        "modelPath": str(MODEL_PATH),
        "labels": CLASS_NAMES,
        "unsafeLabels": sorted(UNSAFE_LABELS),
        "maxVideoFrames": MAX_VIDEO_FRAMES,
    }


@app.post("/moderate")
async def moderate_media(
    file: UploadFile = File(...),
    max_frames: int | None = Form(default=None),
) -> dict[str, Any]:
    content_type = (file.content_type or "").lower()
    file_bytes = await file.read()
    max_bytes = MAX_FILE_MB * 1024 * 1024
    if len(file_bytes) > max_bytes:
        raise HTTPException(status_code=413, detail=f"File must be {MAX_FILE_MB}MB or less.")

    if content_type.startswith("image/"):
        result = _predict_image(_read_image(file_bytes))
        result["frameIndex"] = None
        return _summarize_results([result], "image")

    if content_type.startswith("video/"):
        suffix = Path(file.filename or "upload.mp4").suffix or ".mp4"
        frame_limit = max(1, min(max_frames or MAX_VIDEO_FRAMES, 30))
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name
        try:
            results = []
            for frame_index, frame in _sample_video_frames(tmp_path, frame_limit):
                result = _predict_image(frame)
                result["frameIndex"] = frame_index
                results.append(result)
                if result["unsafeScore"] >= BLOCK_THRESHOLD:
                    break
            return _summarize_results(results, "video")
        finally:
            try:
                os.remove(tmp_path)
            except OSError as e:
                _logger.warning("Failed to remove temp file %s: %s", tmp_path, e)

    raise HTTPException(status_code=400, detail="Only image and video files are supported.")


@app.post("/transcribe")
async def transcribe_audio(
    file: UploadFile = File(...),
    language: str | None = Form(default="vi"),
) -> dict[str, Any]:
    w_model = _require_whisper()
    content_type = (file.content_type or "").lower()

    suffix = ".mp3"
    if "video" in content_type:
        suffix = ".mp4"
    elif "wav" in content_type:
        suffix = ".wav"
    elif "ogg" in content_type:
        suffix = ".ogg"
    elif "m4a" in content_type:
        suffix = ".m4a"

    file_bytes = await file.read()
    max_bytes = MAX_FILE_MB * 1024 * 1024
    if len(file_bytes) > max_bytes:
        raise HTTPException(status_code=413, detail=f"File must be {MAX_FILE_MB}MB or less.")

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(file_bytes)
        tmp_path = tmp.name

    try:
        result = w_model.transcribe(
            tmp_path,
            language=language if language else "vi",
            fp16=False,
        )
        return {
            "text": result.get("text", "").strip(),
            "language": result.get("language", language or "vi"),
            "segments": [
                {
                    "text": seg.get("text", "").strip(),
                    "start": seg.get("start", 0),
                    "end": seg.get("end", 0),
                }
                for seg in result.get("segments", [])
            ],
        }
    except Exception as error:
        raise HTTPException(
            status_code=500, detail=f"Transcription failed: {error}"
        ) from error
    finally:
        try:
            os.remove(tmp_path)
        except OSError as e:
            _logger.warning("Failed to remove temp file %s: %s", tmp_path, e)


@app.post("/transcribe-moderate")
async def transcribe_and_moderate(
    file: UploadFile = File(...),
    language: str | None = Form(default="vi"),
    audio_only: bool = Form(default=False),
) -> dict[str, Any]:
    content_type = (file.content_type or "").lower()

    suffix = ".mp3"
    if "video" in content_type:
        suffix = ".mp4"
    elif "wav" in content_type:
        suffix = ".wav"
    elif "ogg" in content_type:
        suffix = ".ogg"
    elif "m4a" in content_type:
        suffix = ".m4a"

    file_bytes = await file.read()
    max_bytes = MAX_FILE_MB * 1024 * 1024
    if len(file_bytes) > max_bytes:
        raise HTTPException(status_code=413, detail=f"File must be {MAX_FILE_MB}MB or less.")

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(file_bytes)
        tmp_path = tmp.name

    try:
        w_model = _require_whisper()
        transcribe_result = w_model.transcribe(
            tmp_path,
            language=language if language else "vi",
            fp16=False,
        )
        transcribed_text = transcribe_result.get("text", "").strip()

        moderation_result = _moderate_text(transcribed_text)

        return {
            "text": transcribed_text,
            "language": transcribe_result.get("language", language or "vi"),
            "segments": [
                {
                    "text": seg.get("text", "").strip(),
                    "start": seg.get("start", 0),
                    "end": seg.get("end", 0),
                }
                for seg in transcribe_result.get("segments", [])
            ],
            "moderation": moderation_result,
        }
    except Exception as error:
        raise HTTPException(
            status_code=500, detail=f"Transcribe-moderate failed: {error}"
        ) from error
    finally:
        try:
            os.remove(tmp_path)
        except OSError as e:
            _logger.warning("Failed to remove temp file %s: %s", tmp_path, e)


# ---------- text moderation helpers ----------

VIETNAMESE_KEYWORDS = [
    "dm", "đm", "địt", "dit", "cặc", "lồn", "buồi", "cặk", "ngu", "ngụy",
    "chết", "tự sát", "treo cổ", "uống thuốc", "chết đi", "giết", "mày chết",
    "đánh", "đập", "hành hung", "bạo lực", "nude", "sex", "xxx", "porn",
    "khỏa thân", "khiêu dâm", "hentai", "bắn", "nổ", "khủng bố", "bomb",
    "ma túy", "drug", "cần sa", "heroin", "cocaine", "thuốc lắc", "mda",
    "rape", "hiếp", "xâm hại", "lạm dụng", "grooming",
]
# Pre-build a regex that matches each keyword as a whole word (word boundary),
# so "ngu" does not match inside "language" or "bangu".
_KEYWORD_PATTERN = re.compile(
    r'(?<!\w)(' + '|'.join(re.escape(kw) for kw in VIETNAMESE_KEYWORDS) + r')(?!\w)',
    re.IGNORECASE,
)

FLAG_KEYWORD_WEIGHT = 0.5

REVIEW_KEYWORD_WEIGHT = 0.25


def _moderate_text(text: str) -> dict[str, Any]:
    if not text:
        return {
            "isFlagged": False,
            "decision": "APPROVED",
            "flaggedKeywords": [],
            "unsafeScore": 0.0,
        }

    found_keywords = _KEYWORD_PATTERN.findall(text)
    keyword_count = len(found_keywords)

    if keyword_count >= 3:
        unsafe_score = min(1.0, FLAG_KEYWORD_WEIGHT * keyword_count / 3)
    elif keyword_count >= 1:
        unsafe_score = REVIEW_KEYWORD_WEIGHT * keyword_count
    else:
        unsafe_score = 0.0

    if unsafe_score >= BLOCK_THRESHOLD:
        decision = "BLOCKED"
    elif unsafe_score >= REVIEW_THRESHOLD:
        decision = "REVIEW"
    else:
        decision = "APPROVED"

    return {
        "isFlagged": decision != "APPROVED",
        "decision": decision,
        "flaggedKeywords": found_keywords,
        "unsafeScore": round(unsafe_score, 4),
    }
