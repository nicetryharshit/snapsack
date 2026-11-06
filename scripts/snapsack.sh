#!/bin/bash
# Everyday commands for working on SnapSack.
#   ./scripts/snapsack.sh run                 build SnapSack.app, quit any running copy, launch the new one
#   ./scripts/snapsack.sh build               just build build/SnapSack.app
#   ./scripts/snapsack.sh install             copy to ~/Applications (use this one for "Open at Login")
#   ./scripts/snapsack.sh icon                redraw Resources/AppIcon.png (needs: pip3 install pillow)
#   ./scripts/snapsack.sh reset-permissions   clear SnapSack's Accessibility / Screen Recording grants
#   ./scripts/snapsack.sh clean
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SnapSack.app"
BUNDLE_ID="app.snapsack.mac"

case "${1:-run}" in
  build)
    ./scripts/bundle.sh
    ;;
  run)
    ./scripts/bundle.sh
    pkill -x SnapSack 2>/dev/null || true
    sleep 0.3
    open "$APP"
    ;;
  install)
    ./scripts/bundle.sh
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/SnapSack.app"
    cp -R "$APP" "$HOME/Applications/SnapSack.app"
    echo "Installed to ~/Applications/SnapSack.app"
    ;;
  icon)
    python3 tools/make_icon.py
    ;;
  reset-permissions)
    tccutil reset Accessibility "$BUNDLE_ID" || true
    tccutil reset ScreenCapture "$BUNDLE_ID" || true
    ;;
  clean)
    rm -rf build .build
    ;;
  *)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
