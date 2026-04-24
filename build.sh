#!/bin/bash

# Generated with Swift 6 + macOS 15 target build script

set -e # 遇到错误立即停止

# 1. 切换到脚本所在目录
cd "$(dirname "$0")"

# 2. 定义变量
PROJECT_NAME="CoffeePaste"
SCHEME_NAME="CoffeePaste"
BUILD_DIR="./build"

echo "🚀 开始编译 $PROJECT_NAME (Release)..."

# 3. 清理并编译
# 使用 xcodebuild 命令行工具进行编译，直接输出到 ./build
mkdir -p "$BUILD_DIR"
xcodebuild -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -destination 'generic/platform=macOS,name=Any Mac' \
    ARCHS='arm64' \
    ONLY_ACTIVE_ARCH=YES \
    SWIFT_OPTIMIZATION_LEVEL='-O' \
    SWIFT_COMPILATION_MODE=wholemodule \
    GCC_OPTIMIZATION_LEVEL='3' \
    LLVM_LTO=YES \
    DEAD_CODE_STRIPPING=YES \
    STRIP_INSTALLED_PRODUCT=YES \
    COPY_PHASE_STRIP=YES \
    SWIFT_COVERAGE_MAPPING=NO \
    CLANG_ENABLE_CODE_COVERAGE=NO \
    GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO \
    -derivedDataPath "$BUILD_DIR" \
    clean build 2>&1 >"$BUILD_DIR/build.log"

echo "✅ 编译完成！"

# 4. 找到生成的 .app (在 build/Build/Products/Release 下)
APP_PATH=$(find "$BUILD_DIR" -name "${PROJECT_NAME}.app" -type d | grep "Release" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 错误: 找不到生成的 .app 文件"
    exit 1
fi

echo "📦 生成路径: $APP_PATH"

echo "🎉 准备就绪！现在你可以运行 ./install.sh 进行安装了。"
