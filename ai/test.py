import tensorflow as tf
from tensorflow.keras.models import load_model
import numpy as np
import requests
from PIL import Image
from io import BytesIO

# -------------------------------
# 1. Load model
# -------------------------------
model_path = '/content/drive/MyDrive/cencor_last.h5'
model = load_model(model_path)

# -------------------------------
# 2. Class labels (đúng thứ tự)
# -------------------------------
class_names = [
    'baoluc',
    'draw',
    'hentai',
    'phanbiet',
    'sex-nude',
    'wound'
]

# -------------------------------
# 3. Hàm load ảnh từ URL (an toàn)
# -------------------------------
def load_image_from_url(url):
    try:
        headers = {
            "User-Agent": "Mozilla/5.0"
        }
        response = requests.get(url, headers=headers, timeout=10)

        content_type = response.headers.get("Content-Type", "")

        if "image" not in content_type:
            raise ValueError("URL không phải ảnh")

        img = Image.open(BytesIO(response.content)).convert('RGB')
        return img

    except Exception as e:
        print(f"❌ Lỗi load ảnh: {e}")
        return None

# -------------------------------
# 4. URL ảnh
# -------------------------------
url = "https://photo.znews.vn/w660/Uploaded/sgorvz/2025_05_22/vet_thuong_ho.jpg"

img = load_image_from_url(url)

if img is None:
    raise Exception("Không load được ảnh từ URL")

# -------------------------------
# 5. Resize
# -------------------------------
img = img.resize((224, 224))

# -------------------------------
# 6. Preprocess
# -------------------------------
img_array = np.array(img) / 255.0
img_array = np.expand_dims(img_array, axis=0)

# -------------------------------
# 7. Predict
# -------------------------------
pred = model.predict(img_array)
pred_class = np.argmax(pred, axis=1)[0]
pred_prob = np.max(pred)

# -------------------------------
# 8. Decode label
# -------------------------------
pred_label = class_names[pred_class]

# -------------------------------
# 9. Output
# -------------------------------
print(f"Predicted class: {pred_label}")
print(f"Probability: {pred_prob:.4f}")