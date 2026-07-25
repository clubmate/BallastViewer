#!/bin/zsh
# Run the BallastCore logic tests. Fast — no Xcode project build involved.
set -euo pipefail
cd "$(dirname "$0")/.."

# The installed CommandLineTools toolchain is inconsistent (SDK/compiler mismatch);
# use the full Xcode toolchain for SPM as well.
export DEVELOPER_DIR=/Applications/Xcode.app

swift test --package-path BallastCore
