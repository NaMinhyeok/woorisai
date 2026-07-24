#!/bin/zsh

setopt ERR_EXIT NO_UNSET PIPE_FAIL

# CI Verify에서 분리한 UI smoke를 로컬 simulator에서 같은 구성으로 실행한다.
#
# 사용법:
#   apps/ios/scripts/ui-smoke.zsh          # 화면 2종의 핵심 smoke 6개
#   apps/ios/scripts/ui-smoke.zsh --full   # 화면 2종의 전체 WoorisaiUITests

typeset -gr script_dir="${0:A:h}"
typeset -gr repo_root="${script_dir:h:h:h}"
typeset -gr project_path="${repo_root}/apps/ios/Woorisai.xcodeproj"
typeset -gr derived_data_path="${repo_root}/.local/ios-ui-smoke"
typeset -gr iphone_15_destination='platform=iOS Simulator,name=iPhone 15 Pro,OS=26.5'
typeset -gr iphone_13_destination='platform=iOS Simulator,name=iPhone 13 Pro,OS=26.5'

run_full=false
if (( $# > 0 )); then
  case "$1" in
    --full) run_full=true ;;
    *)
      print -u2 -- "usage: ${0} [--full]"
      exit 64
      ;;
  esac
fi

typeset -a iphone_15_tests=(
  WoorisaiUITests/WoorisaiLaunchTests/testSuccessShowsBothParticipantNames
  WoorisaiUITests/WoorisaiLaunchTests/testNumberPadCanBeDismissedWithoutSubmitting
  WoorisaiUITests/WoorisaiLaunchTests/testSlotTwoReversesDirectionalScoresAndDiaryOwnership
)
typeset -a iphone_13_tests=(
  WoorisaiUITests/WoorisaiLaunchTests/testSuccessShowsBothParticipantNames
  WoorisaiUITests/WoorisaiLaunchTests/testAuthenticatedDiaryTabShowsWarmPrivateJournalFailureState
  WoorisaiUITests/WoorisaiLaunchTests/testSuccessSupportsAccessibilityExtraExtraExtraLargeText
)
if [[ "$run_full" == true ]]; then
  iphone_15_tests=(WoorisaiUITests)
  iphone_13_tests=(WoorisaiUITests)
fi

run_ui_tests() {
  local destination="$1"
  shift
  local -a only_testing_flags=()
  local test_identifier
  for test_identifier in "$@"; do
    only_testing_flags+=(-only-testing:"$test_identifier")
  done
  /usr/bin/xcodebuild test-without-building \
    -project "$project_path" \
    -scheme Woorisai \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 600 \
    "${only_testing_flags[@]}" \
    -enableCodeCoverage NO \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO
}

print -- "Building app and test bundles once."
/usr/bin/xcodebuild build-for-testing \
  -project "$project_path" \
  -scheme Woorisai \
  -configuration Debug \
  -destination "$iphone_15_destination" \
  -derivedDataPath "$derived_data_path" \
  -enableCodeCoverage NO \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO

print -- "Running UI smoke on iPhone 15 Pro."
run_ui_tests "$iphone_15_destination" "${iphone_15_tests[@]}"
print -- "Running UI smoke on iPhone 13 Pro."
run_ui_tests "$iphone_13_destination" "${iphone_13_tests[@]}"

print -- "UI smoke passed."
