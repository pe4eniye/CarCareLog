#!/bin/bash
# Runs the screenshot tour (UITests/ScreenshotTour.swift) in demo mode: every screen, sheet and dialog
# is saved into shots/ as <lang>-<NN>-<screen>.png.
# Usage: take-screenshots.sh "uk"   (needs DEVICE_ID and build/dd from the build-for-testing step)
set -euo pipefail
LANGS="${1:-uk}"
mkdir -p shots

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$DEVICE_ID" appearance light

for L in $LANGS; do
  # TEST_RUNNER_-prefixed variables reach the test process without the prefix.
  TEST_RUNNER_SHOTS_DIR="$PWD/shots" TEST_RUNNER_SHOTS_LANG="$L" \
  xcodebuild test-without-building \
    -project CarCareLog.xcodeproj -scheme CarCareLog \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath build/dd \
    -only-testing:CarCareLogUITests/ScreenshotTour \
    > "build/shots-$L.log" 2>&1 || { echo "some tour steps failed (screens still saved):"; \
      grep -E "error:|failed" "build/shots-$L.log" | head -40 || true; }
done
ls -la shots
