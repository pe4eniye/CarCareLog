#!/bin/bash
# Runs the simulator build in demo mode and saves one screenshot per screen into shots/.
# Usage: take-screenshots.sh "uk ru en"   (needs DEVICE_ID and build/dd from the build step)
set -euo pipefail
LANGS="${1:-uk}"
APP=$(find build/dd/Build/Products -name "CarCareLog.app" -maxdepth 3 | head -1)
BUNDLE=com.carcarelog.app

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl status_bar "$DEVICE_ID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$DEVICE_ID" "$APP"

shot() { # name, then app arguments
  local name="$1"; shift
  xcrun simctl terminate "$DEVICE_ID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE" "$@" > /dev/null
  sleep 6
  xcrun simctl io "$DEVICE_ID" screenshot "shots/$name.png" > /dev/null
  echo "saved shots/$name.png"
}

question() {
  case "$1" in
    ru) echo "Когда менять салонный фильтр?" ;;
    en) echo "What is due at 250k?" ;;
    *) echo "Коли я востаннє міняв моторне масло?" ;;
  esac
}
question2() {
  case "$1" in
    ru) echo "Дай номер масляного фильтра" ;;
    en) echo "Oil filter part number" ;;
    *) echo "Що замінити на 240 тис?" ;;
  esac
}

for L in $LANGS; do
  xcrun simctl ui "$DEVICE_ID" appearance light
  # Settings first (UserDefaults argument domain), demo flags last.
  for TAB in home history parts expenses settings; do
    shot "$L-$TAB" -settings.language "$L" -settings.theme light -demo -startTab "$TAB"
  done
  shot "$L-assistant" -settings.language "$L" -settings.theme light -demo -startTab assistant \
    -demoQuestion "$(question "$L")"
  shot "$L-assistant2" -settings.language "$L" -settings.theme light -demo -startTab assistant \
    -demoQuestion "$(question2 "$L")"
  shot "$L-home-dark" -settings.language "$L" -settings.theme dark -demo -startTab home
  shot "$L-onboarding" -settings.language "$L" -settings.theme light -demo -demoOnboarding
done
ls -la shots
