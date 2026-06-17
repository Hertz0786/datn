"""
Test Kiddo Social AI Moderation với ảnh vết thương từ URL.
Chạy trực tiếp model CNN (không cần FastAPI server) để xem quyết định.
"""
import os
import sys
from io import BytesIO
from pathlib import Path

import numpy as np
import requests
import tensorflow as tf
from PIL import Image, ImageOps

# --- Cấu hình ---
BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "ai.h5"
IMAGE_SIZE = 224
BLOCK_THRESHOLD = 0.75
REVIEW_THRESHOLD = 0.55

CLASS_NAMES = ["baoluc", "draw", "hentai", "phanbiet", "sex-nude", "wound"]
UNSAFE_LABELS = {"baoluc", "hentai", "phanbiet", "sex-nude", "wound"}

# --- URL ảnh cần test ---
TEST_IMAGE_URL = (
    "https://shingmarkhospital.com.vn/public/userfiles/news/Khoa_Nhi/"
    "vet-thuong-hoai-tu-khi-vao-vien.jpg"
)


def load_image_from_url(url: str) -> Image.Image:
    headers = {"User-Agent": "Mozilla/5.0"}
    resp = requests.get(url, headers=headers, timeout=20)
    resp.raise_for_status()
    content_type = resp.headers.get("Content-Type", "")
    if "image" not in content_type:
        raise ValueError(f"URL khong phai anh. Content-Type={content_type}")
    return Image.open(BytesIO(resp.content)).convert("RGB")


def preprocess(image: Image.Image) -> np.ndarray:
    image = ImageOps.exif_transpose(image).convert("RGB")
    image = image.resize((IMAGE_SIZE, IMAGE_SIZE))
    arr = np.asarray(image, dtype=np.float32) / 255.0
    return np.expand_dims(arr, axis=0)


def predict(model, image: Image.Image) -> dict:
    x = preprocess(image)
    pred = model.predict(x, verbose=0)[0]
    scores = {label: float(pred[i]) for i, label in enumerate(CLASS_NAMES)}
    top_label = max(scores, key=scores.get)
    unsafe_scores = {l: s for l, s in scores.items() if l in UNSAFE_LABELS}
    unsafe_label = max(unsafe_scores, key=unsafe_scores.get)
    return {
        "scores": scores,
        "topLabel": top_label,
        "topScore": scores[top_label],
        "unsafeLabel": unsafe_label,
        "unsafeScore": unsafe_scores[unsafe_label],
    }


def decide(unsafe_score: float) -> str:
    if unsafe_score >= BLOCK_THRESHOLD:
        return "BLOCKED"
    if unsafe_score >= REVIEW_THRESHOLD:
        return "REVIEW"
    return "APPROVED"


def main() -> int:
    print("=" * 70)
    print(f"Test URL: {TEST_IMAGE_URL}")
    print(f"Model:   {MODEL_PATH}")
    print(f"Thresholds: BLOCK>={BLOCK_THRESHOLD}, REVIEW>={REVIEW_THRESHOLD}")
    print("=" * 70)

    if not MODEL_PATH.exists():
        print(f"Khong tim thay model tai {MODEL_PATH}")
        return 1

    print("Dang load model CNN (co the mat vai giay)...")
    model = tf.keras.models.load_model(MODEL_PATH, compile=False)
    print("Model da load xong.\n")

    print("Dang tai anh tu URL...")
    try:
        img = load_image_from_url(TEST_IMAGE_URL)
    except Exception as e:
        print(f"LOI: Khong tai duoc anh: {e}")
        return 1
    print(f"  - Kich thuoc goc: {img.size}")
    print(f"  - Mode: {img.mode}\n")

    print("Dang chay predict...")
    result = predict(model, img)
    decision = decide(result["unsafeScore"])

    print("=" * 70)
    print("KET QUA:")
    print("=" * 70)
    print(f"{'Label':<12}{'Score':>10}")
    print("-" * 22)
    for label, score in sorted(result["scores"].items(), key=lambda kv: -kv[1]):
        flag = "  <-- UNSAFE" if label in UNSAFE_LABELS else ""
        print(f"{label:<12}{score:>10.4f}{flag}")
    print()
    print(f"Top label (chinh):  {result['topLabel']} ({result['topScore']:.4f})")
    print(f"Unsafe label:       {result['unsafeLabel']} ({result['unsafeScore']:.4f})")
    print(f"DECISION:           {decision}")
    print("=" * 70)

    if decision == "BLOCKED":
        print("=> He thong se TU CHOI bai viet (tra 400 cho client).")
    elif decision == "REVIEW":
        print("=> He thong se CHO ADMIN DUYET (status=pending_review).")
        print("=> Admin se nhin thay bai viet trong trang Content/Media/Reports.")
    else:
        print("=> He thong se CHO PHEP dang bai (status=published).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
