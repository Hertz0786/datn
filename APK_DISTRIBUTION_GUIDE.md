# Hướng dẫn cài đặt & phát hành APK Kiddo Social (ngoài Google Play)

> File APK đã được ký số và sẵn sàng phát hành. Không cần tài khoản Google Play Developer.

## File APK đã tạo

```
D:\Doan\Doan\dist\kidsocial-v1.0.0.apk         (~55 MB)
D:\Doan\Doan\dist\kidsocial-v1.0.0.SHA256.txt  (thông tin chữ ký)
```

**Thông tin chữ ký số (xác minh nguồn gốc):**
- Signer: `CN=Kiddo Social, O=KidSocial, L=Ho Chi Minh, ST=Ho Chi Minh, C=VN`
- Cert SHA-256: `0f4a3d3c7a7d1d48f178fe60faac84e26fbb3f535ca9f46cf4ab770d62fc05e5`
- APK SHA-256: `679AB0C01492311686FC2DC6095FC7E6DBD2E78B24A8528B7ADEE432C2D734DA`
- Package ID: `com.kidsocial.app`
- Version: 1.0.0 (versionCode 1)

## Bước 1 — Backup keystore (BẮT BUỘC)

> ⚠️ File `fe/android/app/key-release.jks` là chìa khoá. Mất = không thể cập nhật app.

```powershell
Copy-Item D:\Doan\Doan\fe\android\app\key-release.jks D:\Backup\
# Hoặc copy lên Google Drive, USB...
```

Password (nếu cần build lại):
- storePassword: `KidSocial2026App!`
- keyPassword: `KidSocial2026App!`
- alias: `kidsocial`

## Bước 2 — Test APK trên thiết bị thật

### Cài bằng ADB (developer)
```powershell
# Bật USB debugging trên điện thoại trước
adb devices
adb install -r D:\Doan\Doan\dist\kidsocial-v1.0.0.apk
```

### Cài thủ công trên điện thoại
1. Copy file `kidsocial-v1.0.0.apk` vào điện thoại (USB, AirDroid, email, Google Drive,...)
2. Mở file bằng trình quản lý file
3. Android sẽ hỏi **"Cho phép cài từ nguồn này?"** → bật quyền → **Cài đặt**

> Lưu ý: Android 8+ mặc định chặn cài APK ngoài Play. Phải bật "Cài từ nguồn không xác định" cho app File Manager tương ứng.

## Bước 3 — Phát hành cho người dùng

### Cách A: Host file APK trên trang web của bạn

Upload `kidsocial-v1.0.0.apk` lên hosting (GitHub Releases, Firebase Hosting, S3, VPS,...)

Ví dụ tạo GitHub Release:
1. Vào https://github.com/Hertz0786/datn/releases
2. Bấm **Create new release** → tag `v1.0.0`
3. Kéo thả file APK vào ô "Attach binaries"
4. Bấm **Publish release**
5. Link tải: `https://github.com/Hertz0786/datn/releases/download/v1.0.0/kidsocial-v1.0.0.apk`

### Cách B: Chia sẻ qua Telegram / Zalo / Group chat

Upload file APK (tối đa 2GB trên Telegram). Gửi link cho người dùng.

### Cách C: Đăng lên các store phụ (miễn phí / rẻ hơn Google Play)

| Store | Phí | Ghi chú |
|---|---|---|
| **F-Droid** | Miễn phí | Cần build từ source công khai, không cho dep Google Play Services |
| **Huawei AppGallery** | Miễn phí | Hỗ trợ cả app dùng GMS nhẹ |
| **Samsung Galaxy Store** | $0 đến $40 | Trừ khi >$1M doanh thu |
| **Xiaomi GetApps** | Miễn phí | |
| **OPPO / Vivo / OnePlus** | Miễn phí | |
| **APKPure / APKMirror** | Miễn phí | Upload APK để cộng đồng tải |

> ⚠️ Lưu ý: Khi đăng lên store phụ, mỗi store có quy trình review riêng, có thể mất 1-7 ngày.

## Bước 4 — Cập nhật app phiên bản mới

Khi có code mới:

```powershell
cd D:\Doan\Doan\fe

# Sửa version trong pubspec.yaml (hoặc truyền flag)
# version: 1.0.1+2 (name+code)

# Clean build cũ
flutter clean

# Build APK mới
flutter build apk --release --dart-define-from-file=.env.production

# Copy ra dist
Copy-Item build\app\outputs\flutter-apk\app-release.apk dist\kidsocial-v1.0.1.apk -Force
```

App cùng package `com.kidsocial.app` sẽ được cập nhật đè lên bản cũ trên thiết bị người dùng (giữ nguyên data).

## Bước 5 — Phiên bản chia nhỏ (tuỳ chọn)

APK hiện tại ~55 MB vì chứa cả 3 kiến trúc (arm64, armeabi-v7a, x86_64). Nếu muốn file nhỏ hơn cho mỗi thiết bị:

```powershell
cd D:\Doan\Doan\fe
flutter build apk --release --dart-define-from-file=.env.production --split-per-abi
```

Sẽ tạo 3 file:
- `app-armeabi-v7a-release.apk` (~22 MB) — điện thoại Android cũ
- `app-arm64-v8a-release.apk` (~24 MB) — điện thoại Android đời mới (đa số)
- `app-x86_64-release.apk` (~26 MB) — máy ảo, Chromebook

Copy cả 3 file vào `dist/` và phát hành.

## Xử lý sự cố thường gặp

### "App not installed" khi cài
- Có thể do app cùng package đã được cài bằng keystore khác. Gỡ app cũ trước rồi cài lại.
- Bật "Unknown sources" trong Settings → Security.

### App mở nhưng không gọi được API
- Kiểm tra điện thoại có truy cập được `http://13.211.170.58` không (mở trình duyệt gõ URL).
- App đã cấu hình cleartext cho `13.211.170.58` qua network_security_config.xml.

### Crash ngay khi mở
- Bật logcat: `adb logcat | Select-String "kidsocial|flutter"`
- Gửi log cho developer.

### Người dùng báo "This app was built for an older version of Android"
- Không nên xảy ra với APK hiện tại (minSdk theo Flutter default 21, tương thích Android 5.0+).
- Nếu xảy ra: rebuild với `--target-platform android-arm64` để giảm kích thước.

## Lệnh build nhanh (cheat sheet)

```powershell
# Build APK release tiêu chuẩn
cd D:\Doan\Doan\fe
flutter build apk --release --dart-define-from-file=.env.production

# Build + copy ra dist
flutter build apk --release --dart-define-from-file=.env.production
Copy-Item build\app\outputs\flutter-apk\app-release.apk dist\kidsocial-v1.0.0.apk -Force

# Verify chữ ký
& "$env:LOCALAPPDATA\Android\sdk\build-tools\35.0.0\apksigner.bat" verify --print-certs dist\kidsocial-v1.0.0.apk
```
