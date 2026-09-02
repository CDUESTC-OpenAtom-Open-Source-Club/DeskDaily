#!/bin/bash
# DeskDaily 一键构建：编译 Swift → 生成图标 → 组装 .app → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeskDaily"
BUILD_DIR="$PWD/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> 清理旧的构建产物"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR"

echo "==> 编译 Swift 源码（约需 1 分钟）…"
swiftc -O -swift-version 5 \
  -target arm64-apple-macos13.0 \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
  Sources/main.swift Sources/Store.swift Sources/KeychainStore.swift Sources/ChatSession.swift Sources/BuiltInTemplates.swift Sources/TemplateCatalogView.swift Sources/ShotExporter.swift Sources/WindowController.swift Sources/ContentView.swift Sources/AIAssistant.swift Sources/StatisticsView.swift Sources/QuickAdd.swift Sources/HotkeyManager.swift Sources/StatusBar.swift

echo "==> 生成应用图标"
if [ ! -f "$BUILD_DIR/AppIcon.icns" ]; then
  swift Scripts/make_icon.swift "$BUILD_DIR/icon_1024.png"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"
fi

echo "==> 组装 .app"
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Ad-hoc 签名（本地运行无需开发者证书）"
xattr -cr "$APP_DIR"
codesign --force --sign - --identifier "local.blackevil.deskdaily" "$APP_DIR" >/dev/null 2>&1

echo "==> 构建完成：$APP_DIR"
