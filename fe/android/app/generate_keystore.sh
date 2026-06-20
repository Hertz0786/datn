#!/usr/bin/env bash
# Script tạo keystore release cho Android. CHẠY 1 LẦN DUY NHẤT.
# Keystore mất = app mất, KHÔNG tái tạo được vì Google Play yêu cầu cùng keystore
# để cập nhật app. Backup file *.jks ở nơi an toàn (Google Drive mã hoá, Bitwarden, v.v.).

set -e

KEYSTORE_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYSTORE_FILE="$KEYSTORE_DIR/key-release.jks"
ALIAS="kidsocial"
VALIDITY=10000

if [ -f "$KEYSTORE_FILE" ]; then
  echo "ERROR: $KEYSTORE_FILE already exists. Refusing to overwrite."
  echo "If you really want a new keystore, delete it first (you will LOSE update capability for existing apps)."
  exit 1
fi

echo "Tao keystore tai: $KEYSTORE_FILE"
echo "Alias: $ALIAS"
echo "Valid: $VALIDITY ngay"
echo ""
echo "Ban se duoc hoi nhap:"
echo "  - Keystore password (storePassword)"
echo "  - Key password (keyPassword) - nen dat giong storePassword de de nho"
echo "  - Thong tin Organization (CN, O, L, S, C)"
echo ""

keytool -genkey -v \
  -keystore "$KEYSTORE_FILE" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 \
  -validity $VALIDITY \
  -alias "$ALIAS"

echo ""
echo "=== Keystore da tao xong ==="
echo "File: $KEYSTORE_FILE"
echo ""
echo "Tiep theo:"
echo "1. Copy file android/key.properties.example thanh android/key.properties"
echo "2. Dien storePassword va keyPassword vua dat vao"
echo "3. Backup file $KEYSTORE_FILE o noi an toan"
echo "4. KHONG commit file *.jks hoac key.properties len git"
