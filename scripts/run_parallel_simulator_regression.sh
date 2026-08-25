#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_ROOT="${ROOT_DIR}/.build/parallel-regression"
RUN_ID="${BODYMODE_REGRESSION_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
REPORT_DIR="${REPORT_ROOT}/${RUN_ID}"
SUMMARY_PATH="${REPORT_DIR}/summary.txt"
STARTED_AT=$(date +%s)
IOS_RUNTIME="${BODYMODE_IOS_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
WATCH_RUNTIME="${BODYMODE_WATCH_RUNTIME:-com.apple.CoreSimulator.SimRuntime.watchOS-26-5}"
IOS_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
WATCH_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"
IPHONE_WORKERS="${BODYMODE_REGRESSION_IPHONE_WORKERS:-2}"
CACHE_ROOT="${REPORT_ROOT}/cache"
IOS_DERIVED_DATA="${CACHE_ROOT}/DerivedData-ios"
WATCH_DERIVED_DATA="${CACHE_ROOT}/DerivedData-watch"
IOS_SCREENSHOT_SUITE="GymTrainingAppUITests/FigmaReferenceScreenshots"
IOS_APP_STORE_SCREENSHOT_SUITE="GymTrainingAppUITests/AppStoreReviewScreenshotUITests"
WATCH_SCREENSHOT_SUITE="GymTrainingWatchAppUITests/WatchFigmaReferenceScreenshots"
RESULT_NAMES=(unit core meals ai settings accessibility analytics watch)
SIMULATORS_TO_SHUTDOWN=()
IOS_INVENTORY_JSON="${REPORT_DIR}/inventory-ios.json"
WATCH_INVENTORY_JSON="${REPORT_DIR}/inventory-watch.json"
IOS_EXECUTED_TESTS="${REPORT_DIR}/executed-ios-tests.txt"
WATCH_EXECUTED_TESTS="${REPORT_DIR}/executed-watch-tests.txt"
GIT_SHA="$(git -C "${ROOT_DIR}" rev-parse --short=12 HEAD 2>/dev/null || printf 'unavailable')"
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]; then
  GIT_STATE="dirty"
else
  GIT_STATE="clean"
fi

summary_written=0
gate_status=1

mkdir -p "${REPORT_DIR}" "${CACHE_ROOT}"
cd "${ROOT_DIR}"

cleanup() {
  local jobs
  local simulator

  jobs=$(jobs -pr)
  if [[ -n "${jobs}" ]]; then
    kill ${jobs} 2>/dev/null || true
  fi

  if [[ "${BODYMODE_KEEP_SIMULATORS_RUNNING:-0}" != "1" ]]; then
    for simulator in "${SIMULATORS_TO_SHUTDOWN[@]}"; do
      xcrun simctl shutdown "${simulator}" 2>/dev/null || true
    done
  fi
}

read_version() {
  local info_plist
  local version
  local build

  info_plist=$(find "${IOS_DERIVED_DATA}/Build/Products" -path '*/GymTrainingApp.app/Info.plist' -print -quit 2>/dev/null || true)
  if [[ -z "${info_plist}" ]]; then
    printf 'unavailable'
    return
  fi

  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}" 2>/dev/null || true)
  build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}" 2>/dev/null || true)
  if [[ -n "${version}" && -n "${build}" ]]; then
    printf '%s (%s)' "${version}" "${build}"
  else
    printf 'unavailable'
  fi
}

is_allowed_skip() {
  case "$1" in
    'IntegrationAndHealthUITests/testWatchPlanTransfer()' | \
      'SettingsAndAccessibilityUITests/testGoogleDemoBannerLoadsWhenNetworkIntegrationTestsAreEnabled()')
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

analyze_result() {
  local name="$1"
  local result_path="${REPORT_DIR}/${name}.xcresult"
  local command_status_path="${REPORT_DIR}/${name}.status"
  local command_status="missing"
  local result_summary
  local test_tree
  local passed
  local failed_count
  local skipped
  local test_count
  local tree_test_count
  local tree_skipped_count
  local identifier
  local result

  if [[ -s "${command_status_path}" ]]; then
    command_status=$(<"${command_status_path}")
  fi
  if [[ "${command_status}" != "0" ]]; then
    printf '%-13s command=%s no valid successful test invocation\n' "${name}" "${command_status}"
    analysis_failed=1
  fi

  if [[ ! -f "${result_path}/Info.plist" ]]; then
    printf '%-13s pass=0 fail=0 skip=0 result=missing\n' "${name}"
    analysis_failed=1
    return
  fi
  if ! result_summary=$(xcrun xcresulttool get test-results summary --path "${result_path}" --compact 2>/dev/null); then
    printf '%-13s pass=0 fail=0 skip=0 result=unreadable\n' "${name}"
    analysis_failed=1
    return
  fi
  if ! test_tree=$(xcrun xcresulttool get test-results tests --path "${result_path}" --compact 2>/dev/null); then
    printf '%-13s pass=0 fail=0 skip=0 result=unreadable-tests\n' "${name}"
    analysis_failed=1
    return
  fi

  if ! passed=$(jq -r '.passedTests // 0' <<<"${result_summary}") || \
    ! failed_count=$(jq -r '.failedTests // 0' <<<"${result_summary}") || \
    ! skipped=$(jq -r '.skippedTests // 0' <<<"${result_summary}"); then
    printf '%-13s result=invalid-summary-json\n' "${name}"
    analysis_failed=1
    return
  fi
  if [[ ! "${passed}" =~ ^[0-9]+$ || ! "${failed_count}" =~ ^[0-9]+$ || ! "${skipped}" =~ ^[0-9]+$ ]]; then
    printf '%-13s result=invalid-counts\n' "${name}"
    analysis_failed=1
    return
  fi

  test_count=$((passed + failed_count + skipped))
  if ! tree_test_count=$(jq -r '[.. | objects | select(.nodeType? == "Test Case")] | length' <<<"${test_tree}") || \
    ! tree_skipped_count=$(jq -r '[.. | objects | select(.nodeType? == "Test Case" and .result == "Skipped")] | length' <<<"${test_tree}"); then
    printf '%-13s result=invalid-test-tree-json\n' "${name}"
    analysis_failed=1
    return
  fi
  printf '%-13s pass=%s fail=%s skip=%s tests=%s\n' \
    "${name}" "${passed}" "${failed_count}" "${skipped}" "${test_count}"
  total_passed=$((total_passed + passed))
  total_failed=$((total_failed + failed_count))
  total_skipped=$((total_skipped + skipped))

  if [[ "${test_count}" -eq 0 || "${failed_count}" -ne 0 ]]; then
    analysis_failed=1
  fi
  if [[ ! "${tree_test_count}" =~ ^[0-9]+$ || ! "${tree_skipped_count}" =~ ^[0-9]+$ || \
    "${tree_test_count}" -ne "${test_count}" || "${tree_skipped_count}" -ne "${skipped}" ]]; then
    printf '  ERROR xcresult summary and test tree counts do not agree\n'
    analysis_failed=1
  fi

  while IFS=$'\t' read -r result identifier; do
    [[ -n "${identifier}" ]] || continue
    if [[ "${name}" == "watch" ]]; then
      printf '%s\n' "${identifier}" >>"${WATCH_EXECUTED_TESTS}"
    else
      printf '%s\n' "${identifier}" >>"${IOS_EXECUTED_TESTS}"
    fi
    case "${identifier}" in
      FigmaReferenceScreenshots/* | AppStoreReviewScreenshotUITests/* | WatchFigmaReferenceScreenshots/*)
        printf '  ERROR screenshot-only test entered the release gate: %s\n' "${identifier}"
        unexpected_screenshots=$((unexpected_screenshots + 1))
        analysis_failed=1
        ;;
    esac

    if [[ "${result}" == "Skipped" ]]; then
      if is_allowed_skip "${identifier}"; then
        printf '  ALLOW skip: %s\n' "${identifier}"
        allowed_skips=$((allowed_skips + 1))
      else
        printf '  ERROR unexpected skip: %s\n' "${identifier}"
        unexpected_skips=$((unexpected_skips + 1))
        analysis_failed=1
      fi
    elif [[ "${result}" != "Passed" ]]; then
      printf '  ERROR test result=%s: %s\n' "${result}" "${identifier}"
      analysis_failed=1
    fi
  done < <(
    jq -r '.. | objects | select(.nodeType? == "Test Case") | [.result, .nodeIdentifier] | @tsv' \
      <<<"${test_tree}"
  )
}

analyze_coverage() {
  local platform="$1"
  local inventory_path="$2"
  local executed_path="$3"
  local expected_path="${REPORT_DIR}/expected-${platform}-tests.txt"
  local missing_path="${REPORT_DIR}/missing-${platform}-tests.txt"
  local extra_path="${REPORT_DIR}/extra-${platform}-tests.txt"
  local expected_count
  local executed_count
  local missing_count
  local extra_count
  local inventory_error_count

  if [[ ! -s "${inventory_path}" ]]; then
    printf '%-13s inventory=missing\n' "${platform}-coverage"
    analysis_failed=1
    return
  fi
  if ! jq -r \
    '.values[]?.enabledTests[]?.identifier | select((split("/") | length) >= 3) | sub("^[^/]+/"; "")' \
    "${inventory_path}" >"${expected_path}"; then
    printf '%-13s inventory=unreadable\n' "${platform}-coverage"
    analysis_failed=1
    return
  fi
  inventory_error_count=$(jq -r '[.errors[]?] | length' "${inventory_path}")
  if [[ ! "${inventory_error_count}" =~ ^[0-9]+$ || "${inventory_error_count}" -ne 0 ]]; then
    printf '%-13s inventory-errors=%s\n' "${platform}-coverage" "${inventory_error_count:-unreadable}"
    analysis_failed=1
  fi

  sort -u -o "${expected_path}" "${expected_path}"
  sort -u -o "${executed_path}" "${executed_path}"
  comm -23 "${expected_path}" "${executed_path}" >"${missing_path}"
  comm -13 "${expected_path}" "${executed_path}" >"${extra_path}"
  expected_count=$(wc -l <"${expected_path}" | tr -d ' ')
  executed_count=$(wc -l <"${executed_path}" | tr -d ' ')
  missing_count=$(wc -l <"${missing_path}" | tr -d ' ')
  extra_count=$(wc -l <"${extra_path}" | tr -d ' ')

  printf '%-13s expected=%s executed=%s missing=%s extra=%s\n' \
    "${platform}-coverage" "${expected_count}" "${executed_count}" "${missing_count}" "${extra_count}"
  if [[ "${expected_count}" -eq 0 || "${missing_count}" -ne 0 || "${extra_count}" -ne 0 ]]; then
    analysis_failed=1
  fi
  while IFS= read -r identifier; do
    [[ -n "${identifier}" ]] && printf '  ERROR expected test did not run: %s\n' "${identifier}"
  done <"${missing_path}"
  while IFS= read -r identifier; do
    [[ -n "${identifier}" ]] && printf '  ERROR unenumerated test entered results: %s\n' "${identifier}"
  done <"${extra_path}"
}

write_summary() {
  local execution_status="$1"
  local version
  local result_label
  local elapsed

  total_passed=0
  total_failed=0
  total_skipped=0
  allowed_skips=0
  unexpected_skips=0
  unexpected_screenshots=0
  analysis_failed=0
  version=$(read_version)
  elapsed=$(($(date +%s) - STARTED_AT))
  : >"${IOS_EXECUTED_TESTS}"
  : >"${WATCH_EXECUTED_TESTS}"

  {
    printf 'BodyMode release regression gate\n'
    printf 'Generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Git SHA: %s\n' "${GIT_SHA}"
    printf 'Working tree: %s\n' "${GIT_STATE}"
    printf 'Version: %s\n' "${version}"
    printf 'Scope: all unit, iPhone UI, and Watch UI tests except screenshot-only suites\n'
    printf 'Screenshot suites: NON-GATING and excluded (%s, %s, %s)\n\n' \
      "${IOS_SCREENSHOT_SUITE}" "${IOS_APP_STORE_SCREENSHOT_SUITE}" "${WATCH_SCREENSHOT_SUITE}"

    for name in "${RESULT_NAMES[@]}"; do
      analyze_result "${name}"
    done
    analyze_coverage ios "${IOS_INVENTORY_JSON}" "${IOS_EXECUTED_TESTS}"
    analyze_coverage watch "${WATCH_INVENTORY_JSON}" "${WATCH_EXECUTED_TESTS}"

    printf '\nTOTAL pass=%s fail=%s skip=%s tests=%s\n' \
      "${total_passed}" "${total_failed}" "${total_skipped}" \
      "$((total_passed + total_failed + total_skipped))"
    printf 'Allowed skips: %s\n' "${allowed_skips}"
    printf 'Unexpected skips: %s\n' "${unexpected_skips}"
    printf 'Unexpected screenshot tests: %s\n' "${unexpected_screenshots}"
    printf 'Elapsed: %ss\n' "${elapsed}"
    printf 'Result bundles and logs: %s\n' "${REPORT_DIR}"

    if [[ "${execution_status}" -ne 0 || "${analysis_failed}" -ne 0 ]]; then
      result_label="FAIL"
      gate_status=1
    else
      result_label="PASS"
      gate_status=0
    fi
    printf 'Gate: %s\n' "${result_label}"
  } >"${SUMMARY_PATH}"
}

on_exit() {
  local status=$?

  trap - EXIT
  cleanup
  if [[ "${summary_written}" -eq 0 ]]; then
    set +e
    write_summary "${status}"
    cat "${SUMMARY_PATH}"
  fi
  exit "${status}"
}

trap on_exit EXIT
trap 'exit 130' INT TERM

if [[ "${IPHONE_WORKERS}" != "1" && "${IPHONE_WORKERS}" != "2" ]]; then
  printf 'BODYMODE_REGRESSION_IPHONE_WORKERS must be 1 or 2.\n' >&2
  exit 2
fi

simulator_id() {
  local name="$1"
  local device_type="$2"
  local runtime="$3"
  local existing

  existing=$(xcrun simctl list devices available | sed -n "s/^[[:space:]]*${name} (\([0-9A-F-]*\)).*/\1/p" | head -1)
  if [[ -n "${existing}" ]]; then
    printf '%s' "${existing}"
  else
    xcrun simctl create "${name}" "${device_type}" "${runtime}"
  fi
}

boot_simulator() {
  local id="$1"

  xcrun simctl shutdown "${id}" 2>/dev/null || true
  xcrun simctl boot "${id}"
  xcrun simctl bootstatus "${id}" -b >/dev/null
}

run_ios_group() {
  local group="$1"
  local simulator="$2"
  local status

  shift 2
  if xcodebuild test-without-building -quiet \
    -xctestrun "${IOS_XCTESTRUN}" \
    -destination "platform=iOS Simulator,id=${simulator}" \
    -retry-tests-on-failure \
    -test-iterations 2 \
    -skip-testing:"${IOS_SCREENSHOT_SUITE}" \
    -skip-testing:"${IOS_APP_STORE_SCREENSHOT_SUITE}" \
    -resultBundlePath "${REPORT_DIR}/${group}.xcresult" \
    "$@" >"${REPORT_DIR}/${group}.log" 2>&1; then
    status=0
  else
    status=$?
  fi
  printf '%s\n' "${status}" >"${REPORT_DIR}/${group}.status"
  return "${status}"
}

run_watch_group() {
  local simulator="$1"
  local status

  if xcodebuild test-without-building -quiet \
    -xctestrun "${WATCH_XCTESTRUN}" \
    -destination "platform=watchOS Simulator,id=${simulator}" \
    -retry-tests-on-failure \
    -test-iterations 2 \
    -only-testing:GymTrainingWatchAppUITests/GymTrainingWatchAppUITests \
    -skip-testing:"${WATCH_SCREENSHOT_SUITE}" \
    -resultBundlePath "${REPORT_DIR}/watch.xcresult" \
    >"${REPORT_DIR}/watch.log" 2>&1; then
    status=0
  else
    status=$?
  fi
  printf '%s\n' "${status}" >"${REPORT_DIR}/watch.status"
  return "${status}"
}

IPHONE_A_ID=$(simulator_id "BodyMode QA Core" "${IOS_DEVICE_TYPE}" "${IOS_RUNTIME}")
if [[ "${IPHONE_WORKERS}" == "1" ]]; then
  IPHONE_B_ID="${IPHONE_A_ID}"
else
  IPHONE_B_ID=$(simulator_id "BodyMode QA Meals" "${IOS_DEVICE_TYPE}" "${IOS_RUNTIME}")
fi
WATCH_ID=$(simulator_id "BodyMode QA Watch 2" "${WATCH_DEVICE_TYPE}" "${WATCH_RUNTIME}")
SIMULATORS_TO_SHUTDOWN=("${IPHONE_A_ID}" "${WATCH_ID}")
if [[ "${IPHONE_WORKERS}" == "2" ]]; then
  SIMULATORS_TO_SHUTDOWN+=("${IPHONE_B_ID}")
fi

boot_pids=()
iphone_ids=("${IPHONE_A_ID}")
if [[ "${IPHONE_WORKERS}" == "2" ]]; then
  iphone_ids+=("${IPHONE_B_ID}")
fi
for id in "${iphone_ids[@]}"; do
  boot_simulator "${id}" &
  boot_pids+=("$!")
done
for pid in "${boot_pids[@]}"; do
  wait "${pid}"
done

xcodebuild build-for-testing -quiet \
  -project GymTrainingApp.xcodeproj \
  -scheme GymTrainingApp \
  -destination "platform=iOS Simulator,id=${IPHONE_A_ID}" \
  -derivedDataPath "${IOS_DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${ROOT_DIR}/.build/SourcePackages" \
  >"${REPORT_DIR}/build-ios.log" 2>&1

xcodebuild build-for-testing -quiet \
  -project GymTrainingApp.xcodeproj \
  -scheme GymTrainingWatchApp \
  -destination "platform=watchOS Simulator,id=${WATCH_ID}" \
  -derivedDataPath "${WATCH_DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${ROOT_DIR}/.build/SourcePackages" \
  >"${REPORT_DIR}/build-watch.log" 2>&1
xcrun simctl shutdown "${WATCH_ID}" 2>/dev/null || true

IOS_XCTESTRUN=$(find "${IOS_DERIVED_DATA}/Build/Products" -name '*.xctestrun' -print -quit)
WATCH_XCTESTRUN=$(find "${WATCH_DERIVED_DATA}/Build/Products" -name '*.xctestrun' -print -quit)
if [[ -z "${IOS_XCTESTRUN}" || -z "${WATCH_XCTESTRUN}" ]]; then
  printf 'Failed to locate prebuilt xctestrun files.\n' >&2
  exit 1
fi

xcodebuild test-without-building -quiet \
  -xctestrun "${IOS_XCTESTRUN}" \
  -destination "platform=iOS Simulator,id=${IPHONE_A_ID}" \
  -skip-testing:"${IOS_SCREENSHOT_SUITE}" \
  -skip-testing:"${IOS_APP_STORE_SCREENSHOT_SUITE}" \
  -enumerate-tests \
  -test-enumeration-style flat \
  -test-enumeration-format json \
  -test-enumeration-output-path "${IOS_INVENTORY_JSON}" \
  >"${REPORT_DIR}/inventory-ios.log" 2>&1

run_iphone_a_lane() {
  local status=0

  run_ios_group unit "${IPHONE_A_ID}" \
    -only-testing:GymTrainingAppTests || status=1
  run_ios_group core "${IPHONE_A_ID}" \
    -only-testing:GymTrainingAppUITests/IntegrationAndHealthUITests \
    -only-testing:GymTrainingAppUITests/WorkoutFlowUITests \
    -only-testing:GymTrainingAppUITests/InitialSetupUITests \
    -only-testing:GymTrainingAppUITests/BeginnerOnboardingUITests || status=1
  run_ios_group ai "${IPHONE_A_ID}" \
    -only-testing:GymTrainingAppUITests/AITrainerUITests \
    -only-testing:GymTrainingAppUITests/OmakaseModeUITests || status=1
  return "${status}"
}

run_iphone_b_lane() {
  local status=0

  run_ios_group meals "${IPHONE_B_ID}" \
    -only-testing:GymTrainingAppUITests/BodyAndNutritionUITests || status=1
  run_ios_group settings "${IPHONE_B_ID}" \
    -only-testing:GymTrainingAppUITests/SettingsAndAccessibilityUITests \
    -skip-testing:GymTrainingAppUITests/SettingsAndAccessibilityUITests/testCoreScreensPassAutomatedAccessibilityAudit \
    -skip-testing:GymTrainingAppUITests/SettingsAndAccessibilityUITests/testUsageAnalyticsIsOptInAndLocallyManageable || status=1
  boot_simulator "${IPHONE_B_ID}" || status=1
  run_ios_group accessibility "${IPHONE_B_ID}" \
    -only-testing:GymTrainingAppUITests/SettingsAndAccessibilityUITests/testCoreScreensPassAutomatedAccessibilityAudit || status=1
  boot_simulator "${IPHONE_B_ID}" || status=1
  run_ios_group analytics "${IPHONE_B_ID}" \
    -only-testing:GymTrainingAppUITests/SettingsAndAccessibilityUITests/testUsageAnalyticsIsOptInAndLocallyManageable || status=1
  return "${status}"
}

execution_status=0
if [[ "${IPHONE_WORKERS}" == "1" ]]; then
  run_iphone_a_lane || execution_status=1
  run_iphone_b_lane || execution_status=1
else
  # Watch runs afterward so CoreSimulator handles at most two XCTest UI sessions.
  run_iphone_a_lane &
  lane_iphone_a_pid=$!
  run_iphone_b_lane &
  lane_iphone_b_pid=$!
  wait "${lane_iphone_a_pid}" || execution_status=1
  wait "${lane_iphone_b_pid}" || execution_status=1
fi
boot_simulator "${WATCH_ID}" || execution_status=1
xcodebuild test-without-building -quiet \
  -xctestrun "${WATCH_XCTESTRUN}" \
  -destination "platform=watchOS Simulator,id=${WATCH_ID}" \
  -only-testing:GymTrainingWatchAppUITests \
  -skip-testing:"${WATCH_SCREENSHOT_SUITE}" \
  -enumerate-tests \
  -test-enumeration-style flat \
  -test-enumeration-format json \
  -test-enumeration-output-path "${WATCH_INVENTORY_JSON}" \
  >"${REPORT_DIR}/inventory-watch.log" 2>&1 || execution_status=1
run_watch_group "${WATCH_ID}" || execution_status=1

write_summary "${execution_status}"
summary_written=1
cat "${SUMMARY_PATH}"
exit "${gate_status}"
