# Kiddo AI Media Moderation Server

Server này load `ai/ai.h5` và cung cấp API kiểm duyệt ảnh/video trước khi backend upload media lên Cloudinary.

## Cài đặt

```powershell
cd ai
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Chạy server

```powershell
cd ai
.\.venv\Scripts\Activate.ps1
uvicorn server:app --host 127.0.0.1 --port 8001
```

## Cấu hình backend

Thêm vào `be/.env`:

```env
AI_MODERATION_URL=http://127.0.0.1:8001
AI_MODERATION_ENABLED=true
AI_MODERATION_FAIL_OPEN=false
AI_MODERATION_TIMEOUT_MS=60000
```

Sau đó restart backend Node.js.

## API

- `GET /health`: kiểm tra model đã load.
- `POST /moderate`: multipart field `file`, nhận ảnh hoặc video.

Video sẽ được lấy mẫu tối đa 12 frame mặc định, phân bổ đều theo độ dài video. Nếu phát hiện frame vượt ngưỡng block thì server dừng sớm để giảm tải.
