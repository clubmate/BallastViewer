#!/bin/zsh
# Build the app from the CLI. Regenerates the Xcode project first, so it is
# always safe to run after adding/removing source files.
set -euo pipefail
cd "$(dirname "$0")/.."

# xcode-select on this machine points at CommandLineTools; xcodebuild needs the full Xcode.
export DEVELOPER_DIR=/Applications/Xcode.app

xcodegen generate
xcodebuild -project ballastviewer.xcodeproj \
  -scheme ballastviewer \
  -configuration Debug \
  -derivedDataPath build \
  -quiet build

echo "Built: build/Build/Products/Debug/ballastviewer.app"
