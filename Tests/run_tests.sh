#!/bin/bash
# DeskDaily 核心逻辑测试：编译纯逻辑源文件 + Tests/main.swift 并运行断言
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 编译测试目标…"
mkdir -p build/tests
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/Store.swift \
  Sources/KeychainStore.swift \
  Sources/OccurrenceKit.swift \
  Sources/AIAssistant.swift \
  Tests/main.swift \
  -o build/tests/dd_tests 2>&1 | grep -E "error" && exit 1 || true

if [ ! -x build/tests/dd_tests ]; then
  echo "编译失败" >&2
  exit 1
fi

echo "==> 运行测试…"
./build/tests/dd_tests
