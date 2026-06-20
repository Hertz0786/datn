# Script tạo keystore release cho Android trên Windows PowerShell. CHẠY 1 LẦN DUY NHẤT.
# Keystore mất = app mất, KHÔNG tái tạo được vì Google Play yêu cầu cùng keystore
# để cập nhật app. Backup file *.jks ở nơi an toàn (Google Drive mã hoá, Bitwarden, v.v.).

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KeyFile   = Join-Path $ScriptDir "key-release.jks"
$Alias     = "kidsocial"
$Validity  = 10000

if (Test-Path $KeyFile) {
  Write-Host "ERROR: $KeyFile da ton tai. Khong ghi de." -ForegroundColor Red
  Write-Host "Neu that su muon keystore moi, xoa no truoc (se MAT kha nang cap nhat app da publish)."
  exit 1
}

Write-Host "Tao keystore tai: $KeyFile"
Write-Host "Alias: $Alias"
Write-Host "Valid: $Validity ngay"
Write-Host ""
Write-Host "Ban se duoc hoi nhap:"
Write-Host "  - Keystore password (storePassword)"
Write-Host "  - Key password (keyPassword) - nen dat giong storePassword de de nho"
Write-Host "  - Thong tin Organization (CN, O, L, S, C)"
Write-Host ""

keytool -genkey -v `
  -keystore $KeyFile `
  -storetype JKS `
  -keyalg RSA -keysize 2048 `
  -validity $Validity `
  -alias $Alias

Write-Host ""
Write-Host "=== Keystore da tao xong ===" -ForegroundColor Green
Write-Host "File: $KeyFile"
Write-Host ""
Write-Host "Tiep theo:"
Write-Host "1. Copy file fe/android/key.properties.example thanh fe/android/key.properties"
Write-Host "2. Dien storePassword va keyPassword vua dat vao"
Write-Host "3. Backup file $KeyFile o noi an toan"
Write-Host "4. KHONG commit file *.jks hoac key.properties len git"
