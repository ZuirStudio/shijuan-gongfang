#!/usr/bin/env bash
# 在 Mac 上生成「未签名 .ipa」，用于 Sideloadly / AltStore / TrollStore 自签安装
# 用法：先装 Xcode（App Store）与 XcodeGen（brew install xcodegen），然后 ./build-ipa.sh
set -euo pipefail
cd "$(dirname "$0")"

APP=ShijuanGongfang
SCHEME=ShijuanGongfang
BUILD=build
OUT=试卷工坊-unsigned.ipa

if ! command -v xcodebuild >/dev/null; then
  echo "找不到 xcodebuild：请先安装 Xcode 并执行 sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null; then
  echo "找不到 xcodegen：请执行 brew install xcodegen（或手动在 Xcode 新建工程导入源码）" >&2
  exit 1
fi

xcodegen generate

xcodebuild \
  -project "$APP.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP_PATH=$(find "$BUILD/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP_PATH" ]; then
  echo "没有产出 .app，构建失败" >&2
  exit 1
fi

rm -rf Payload "$OUT"
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry "$OUT" Payload
rm -rf Payload

echo "已生成：$(pwd)/$OUT"
