#!/bin/zsh

set -euo pipefail

if (( $# != 3 )); then
  print -u2 -- "usage: $0 <device-name> <debug-app-path> <output-directory>"
  exit 64
fi

device_name=$1
app_path=$2
output_directory=$3
bundle_id=com.naminhyeok.woorisai
scenario_token_argument=--login-options-ui-test-token
scenario_marker_name=woorisai-active-ui-test-scenario

case "$device_name" in
  "iPhone 15 Pro" | "iPhone 13 Pro") ;;
  *)
    print -u2 -- "unsupported verification device: $device_name"
    exit 64
    ;;
esac

if [[ ! -d "$app_path" || ! -f "$app_path/Info.plist" ]]; then
  print -u2 -- "debug app bundle not found: $app_path"
  exit 66
fi

actual_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")
if [[ "$actual_bundle_id" != "$bundle_id" ]]; then
  print -u2 -- "unexpected app bundle ID: $actual_bundle_id"
  exit 65
fi

build_configuration=$(
  /usr/libexec/PlistBuddy -c 'Print :WoorisaiBuildConfiguration' "$app_path/Info.plist"
)
if [[ "$build_configuration" != "Debug" ]]; then
  print -u2 -- "UI capture requires a Debug app, got: $build_configuration"
  exit 65
fi

mkdir -p -- "$output_directory"
capture_lock="${TMPDIR:-/tmp}/woorisai-login-options-ui-capture.lock"
if ! mkdir -- "$capture_lock" 2>/dev/null; then
  print -u2 -- "another login-options UI capture is already running"
  exit 75
fi

warmup_screenshot=""
original_content_size=""
cleanup() {
  if [[ -n "$original_content_size" ]]; then
    xcrun simctl ui "$device_name" content_size "$original_content_size" >/dev/null 2>&1 || true
  fi
  if [[ -n "$warmup_screenshot" ]]; then
    rm -f -- "$warmup_screenshot"
  fi
  rmdir -- "$capture_lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
warmup_screenshot=$(mktemp "$output_directory/.login-options-warmup.XXXXXX")

xcrun simctl boot "$device_name" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$device_name" -b >/dev/null
original_content_size=$(xcrun simctl ui "$device_name" content_size)
xcrun simctl install "$device_name" "$app_path"
app_data_container=$(xcrun simctl get_app_container "$device_name" "$bundle_id" data)
scenario_marker="$app_data_container/tmp/$scenario_marker_name"

typeset -a verification_cases=(
  "failureThenSuccess:failure"
  "loading:loading"
  "success:success"
  "longNames:success-accessibility-xxxl"
  "unavailableThenSuccess:unavailable"
)

for verification_case in "${verification_cases[@]}"; do
  scenario=${verification_case%%:*}
  screenshot_name=${verification_case#*:}
  launch_token="$scenario-$$-$RANDOM"
  typeset -a launch_arguments=(
    --login-options-ui-test-scenario
    "$scenario"
    "$scenario_token_argument"
    "$launch_token"
  )
  target_content_size=$original_content_size

  if [[ "$scenario" == "longNames" ]]; then
    target_content_size=accessibility-extra-extra-extra-large
  fi

  xcrun simctl ui "$device_name" content_size "$target_content_size" >/dev/null
  xcrun simctl launch --terminate-running-process \
    "$device_name" "$bundle_id" "${launch_arguments[@]}" >/dev/null
  sleep 3
  active_scenario=""
  if [[ -f "$scenario_marker" ]]; then
    active_scenario=$(<"$scenario_marker")
  fi
  expected_scenario="$scenario:$launch_token"
  if [[ "$active_scenario" != "$expected_scenario" ]]; then
    print -u2 -- "expected scenario marker $expected_scenario, app reported: $active_scenario"
    exit 70
  fi
  # The iOS 26.5 simulator can return an incremental framebuffer on the first
  # screenshot request. Consume that frame before saving the visual artifact.
  xcrun simctl io "$device_name" screenshot --type=png --mask=ignored \
    "$warmup_screenshot" >/dev/null 2>&1
  xcrun simctl io "$device_name" screenshot --mask=ignored \
    "$output_directory/login-options-$screenshot_name.png" >/dev/null 2>&1
done

print -r -- "Captured ${#verification_cases[@]} UI states in $output_directory"
