#!/bin/bash
set -e

# 设置工作目录为脚本所在目录
cd "$(dirname "$0")"

echo "清理构建目录..."
rm -rf build
rm -f TVBox-macOS.dmg

echo "开始构建 macOS 版本..."
xcodebuild -project tvbox.xcodeproj -scheme tvbox-macOS -configuration Release SYMROOT="$(pwd)/build" clean build

APP_PATH="build/Release/TVBox.app"

if [ ! -d "$APP_PATH" ]; then
    echo "错误: 找不到构建好的 App: $APP_PATH"
    exit 1
fi

echo "创建 DMG 安装临时目录..."
DMG_DIR="build/dmg_stage"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

echo "复制 App 至临时目录..."
cp -R "$APP_PATH" "$DMG_DIR/"

echo "创建 Applications 快捷方式..."
ln -s /Applications "$DMG_DIR/Applications"

echo "创建 DMG 安装包..."
hdiutil create -volname "TVBox" -srcfolder "$DMG_DIR" -ov -format UDZO "TVBox-macOS.dmg"

echo "✅ 打包完成！生成文件: TVBox-macOS.dmg"
