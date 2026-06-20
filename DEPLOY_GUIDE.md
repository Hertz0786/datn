# Hướng dẫn Deploy Kiddo Social lên Google Play

Dự án này đã được chuẩn bị sẵn phần lớn để đẩy lên Google Play. Bạn cần làm thêm các bước dưới đây.

---

## 1. Tạo Google Play Developer account (làm 1 lần)

Phí đăng ký: **$25/lần** (một lần duy nhất).

1. Truy cập https://play.google.com/console
2. Đăng nhập bằng tài khoản Google cá nhân/công ty
3. Bấm **Create developer account**
4. Điền:
   - Developer name: `Kiddo Social` (hiển thị trên Play Store)
   - Email liên hệ
   - Số điện thoại
5. Thanh toán $25 bằng thẻ quốc tế
6. Chờ Google xác minh (có thể mất 24-48 giờ)

---

## 2. Tạo app mới trên Play Console

Sau khi account được duyệt:

1. Vào https://play.google.com/console → **Create app**
2. Điền:
   - App name: `Kiddo Social`
   - Default language: `English`
   - App or game: **App**
   - Free or paid: **Free**
3. Chấp nhận các chính sách → **Create app**

---

## 3. Tạo keystore release (LÀM 1 LẦN DUY NHẤT)

> ⚠️ QUAN TRỌNG: File keystore là "chìa khoá" của app trên Play Store. Mất keystore = KHÔNG THỂ cập nhật app. Backup ở nhiều nơi an toàn.

### Trên Windows (PowerShell):

```powershell
cd D:\Doan\Doan\fe\android\app
.\generate_keystore.ps1
```

Lệnh sẽ hỏi:
- **Keystore password** (storePassword): đặt mật khẩu mạnh, ví dụ `KidSocial@2026!`
- **Key password** (keyPassword): nên đặt giống storePassword cho dễ nhớ
- Thông tin Organization: `CN=Kiddo, O=KidSocial, L=HCM, S=HoChiMinh, C=VN`

Sau khi chạy xong, file `key-release.jks` sẽ xuất hiện.

### Tạo file key.properties:

```powershell
Copy-Item ..\key.properties.example ..\key.properties
notepad ..\key.properties
```

Điền lại password bạn vừa đặt:

```properties
storeFile=key-release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=kidsocial
keyPassword=YOUR_KEY_PASSWORD
```

### Upload app signing lên Google Play Console (BẮT BUỘC cho Play Store):

1. Vào **Setup → App signing** trong Play Console
2. Google hỏi: dùng **Google Play App Signing** (khuyến nghị) hay tự quản lý
3. Chọn **Use Google Play App Signing** → Google sẽ hỏi upload keystore
4. Chạy lệnh sau để lấy SHA-256 fingerprint:

```bash
keytool -list -v -keystore key-release.jks -alias kidsocial
```

5. Upload file `key-release.jks` lên Play Console khi được yêu cầu
6. **Backup file này ở 2-3 nơi**: Google Drive mã hoá, USB, Bitwarden,...

---

## 4. Tạo Service Account JSON (cho CI/CD upload tự động)

Service account cho phép GitHub Actions upload AAB thay bạn.

### Bước 4.1: Tạo service account

1. Vào https://console.cloud.google.com/
2. Tạo project mới (hoặc dùng project hiện có): `kidsocial-play-deploy`
3. Vào **APIs & Services → Library** → bật **Google Play Android Developer API**
4. Vào **APIs & Services → Credentials → Create credentials → Service account**
5. Điền:
   - Service account name: `github-actions-play-upload`
   - Service account ID: tự sinh
6. Role: **Owner** (hoặc tối thiểu Play Console Admin)
7. Bấm **Done**
8. Click vào service account vừa tạo → **Keys → Add Key → Create new key → JSON**
9. File JSON sẽ tải về — **đặt tên** `play-service-account.json`, **lưu nơi an toàn**

### Bước 4.2: Cấp quyền trên Play Console

1. Vào Play Console → **Setup → API access**
2. Bấm **Link project** với project GCP ở bước 4.1
3. Trong phần **Service accounts**, click vào account `github-actions-play-upload`
4. Bấm **Grant access** → chọn:
   - **App access**: chọn app `Kiddo Social`
   - **Permissions**: bật ít nhất: Release to production, Roll out releases, View app information
5. **Invite user** → xong

### Bước 4.3: Mã hoá service account JSON thành base64

Mở PowerShell, chạy:

```powershell
cd D:\path\to\downloaded
$json = Get-Content -Raw "play-service-account.json"
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)) | Set-Clipboard
```

Paste vào GitHub Secret (bước 5.2).

---

## 5. Push code lên GitHub và cấu hình secrets

### 5.1. Push code

```powershell
cd D:\Doan\Doan
git add .
git commit -m "Prepare for Google Play deployment"
git push origin main
```

> Nếu gặp lỗi keystore/key.properties bị ignore (đúng rồi, đã ignore), không sao.

### 5.2. Thêm GitHub Secrets

Vào https://github.com/Hertz0786/datn/settings/secrets/actions → **New repository secret**:

| Secret name | Giá trị |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Mã hoá file `key-release.jks` thành base64:<br/>`[Convert]::ToBase64String([IO.File]::ReadAllBytes("key-release.jks"))` |
| `ANDROID_STORE_PASSWORD` | Mật khẩu keystore bạn đặt |
| `ANDROID_KEY_ALIAS` | `kidsocial` |
| `ANDROID_KEY_PASSWORD` | Mật khẩu key bạn đặt |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Toàn bộ nội dung file `play-service-account.json` (paste thẳng) |

---

## 6. Build & upload AAB thủ công (lần đầu tiên)

### Cách 1: Từ máy local

```powershell
cd D:\Doan\Doan\fe

# Tạo keystore (nếu chưa)
cd android\app; .\generate_keystore.ps1; cd ..\..

# Tạo key.properties từ file example
Copy-Item android\key.properties.example android\key.properties
# Sửa password trong key.properties bằng Notepad

# Build AAB
flutter build appbundle --release --dart-define-from-file=.env.production
```

File AAB ở: `fe\build\app\outputs\bundle\release\app-release.aab`

### Upload thủ công lên Play Console (lần đầu nên làm vậy)

1. Vào Play Console → chọn app `Kiddo Social`
2. Vào **Release → Production → Create new release**
3. Bấm **Upload** → chọn file `.aab` vừa build
4. Đặt **Release name**: `1.0.0 (1)`
5. Release notes (copy từ `fe/android/fastlane/whatsnew/en-US.txt`)
6. Bấm **Review release → Start rollout to Production**

### Cách 2: Qua CI/CD (từ lần thứ 2)

Trên GitHub → tab **Actions** → chọn workflow **Build & Deploy Android to Google Play** → **Run workflow**:
- Track: `internal` (test nội bộ) hoặc `production`
- Version name: `1.0.0`
- Version code: `1`

Sau khi test internal OK, đổi track sang `production`.

### Cách 3: Tự động qua tag (khuyến nghị khi đã ổn định)

```powershell
cd D:\Doan\Doan
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions sẽ tự động build và upload lên track `internal`.

---

## 7. Hoàn thiện Store Listing trên Play Console

Trước khi rollout production, Play Console yêu cầu:

### 7.1. Store presence
- **App name**: Kiddo Social
- **Short description** (80 ký tự)
- **Full description** (4000 ký tự)
- **App icon**: 512x512 PNG
- **Feature graphic**: 1024x500 PNG
- **Screenshots**: tối thiểu 2 cái (điện thoại), 1024x500 cho tablet

### 7.2. Content rating
- Vào **Policy → App content → Content rating** → làm questionnaire

### 7.3. Target audience & content
- **Target age group**: chọn
- **Data safety**: khai báo dữ liệu thu thập (email, tên, ảnh)

### 7.4. Privacy policy
- Cần URL policy (host trên GitHub Pages hoặc trang chủ). Ví dụ: `https://kidsocial.app/privacy`

### 7.5. App category
- Chọn category: **Social** hoặc **Communication**

---

## 8. Cấu hình backend cho production

Khi backend `http://13.211.170.58` chuyển sang HTTPS (khuyến nghị), sửa file `fe/.env.production`:

```env
API_BASE_URL=https://api.kidsocial.app
```

Và xoá dòng cleartext cho `13.211.170.58` trong `network_security_config.xml` (sẽ tự động không cho phép HTTP nữa).

---

## 9. Phụ lục: Cấu trúc file đã thay đổi

```
fe/
├── android/
│   ├── app/
│   │   ├── build.gradle.kts          [SỬA] signing release + minify
│   │   ├── proguard-rules.pro        [MỚI] ProGuard config
│   │   ├── generate_keystore.ps1     [MỚI] Script tạo keystore (Windows)
│   │   ├── generate_keystore.sh      [MỚI] Script tạo keystore (Mac/Linux)
│   │   └── src/main/
│   │       ├── AndroidManifest.xml   [SỬA] label + networkSecurityConfig
│   │       ├── kotlin/com/kidsocial/app/MainActivity.kt  [DI CHUYỂN]
│   │       └── res/xml/network_security_config.xml  [MỚI]
│   ├── fastlane/
│   │   └── whatsnew/
│   │       ├── en-US.txt             [MỚI] Release notes tiếng Anh
│   │       └── vi-VN.txt             [MỚI] Release notes tiếng Việt
│   ├── key.properties.example        [MỚI] Template cho key.properties
│   └── (key.properties + *.jks       [KHÔNG COMMIT, đã ignore])
├── .env.production                   [MỚI] Production env

.github/workflows/
└── deploy-android.yml                [MỚI] CI/CD workflow

.gitignore                           [SỬA] Ignore keystore, key.properties, JSON
```

---

## 10. Lệnh nhanh tham khảo

```powershell
# Build AAB local
cd D:\Doan\Doan\fe
flutter clean
flutter pub get
flutter build appbundle --release --dart-define-from-file=.env.production

# Xác minh keystore
keytool -list -v -keystore android\app\key-release.jks -alias kidsocial

# Test release trên thiết bị thật
flutter build apk --release --dart-define-from-file=.env.production
adb install build\app\outputs\flutter-apk\app-release.apk
```

Nếu gặp lỗi trong quá trình deploy, gửi log cho mình nhé.
