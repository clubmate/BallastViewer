#!/bin/zsh
# Build the app from the CLI. Regenerates the Xcode project first, so it is
# always safe to run after adding/removing source files.
set -euo pipefail
cd "$(dirname "$0")/.."

# xcode-select on this machine points at CommandLineTools; xcodebuild needs the full Xcode.
export DEVELOPER_DIR=/Applications/Xcode.app

# Version = number of commits; a dirty tree counts as the commit it is about
# to become, so every change bumps the number shown in About.
BUILD_NUMBER=$(git rev-list --count HEAD)
if [[ -n "$(git status --porcelain)" ]]; then
  BUILD_NUMBER=$((BUILD_NUMBER + 1))
fi

xcodegen generate
xcodebuild -project BallastViewer.xcodeproj \
  -scheme BallastViewer \
  -configuration Debug \
  -derivedDataPath build \
  MARKETING_VERSION="0.1.$BUILD_NUMBER" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -quiet build

echo "Built: build/Build/Products/Debug/BallastViewer.app"
