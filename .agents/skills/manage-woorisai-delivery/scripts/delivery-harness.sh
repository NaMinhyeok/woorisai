#!/usr/bin/env bash

set +x
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null) || {
  printf 'ERROR: delivery harness must run inside the Woorisai Git worktree.\n' >&2
  exit 2
}

usage() {
  printf '%s\n' \
    'usage: delivery-harness.sh preflight|backend|local-smoke|ios|all'
}

require_command() {
  local command_name=$1

  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'ERROR: required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
}

file_mode() {
  local path=$1

  if stat -f '%Lp' "$path" >/dev/null 2>&1; then
    stat -f '%Lp' "$path"
  else
    stat -c '%a' "$path"
  fi
}

run_preflight() {
  local env_path mode untracked_path=''
  local -a env_paths=(
    backend/.env.local
    backend/.env.production
    apps/ios/.env.local
    apps/ios/.env.production
  )

  cd "$repo_root"
  while IFS= read -r -d '' untracked_path; do
    break
  done < <(git ls-files --others --exclude-standard -z)
  if [[ -n "$untracked_path" ]]; then
    printf '%s\n' \
      'ERROR: non-ignored untracked files must be staged or removed before delivery preflight.' \
      >&2
    return 1
  fi
  if ! git diff --quiet --; then
    printf '%s\n' \
      'ERROR: working tree differs from the staged index; stage or restore it before delivery preflight.' \
      >&2
    return 1
  fi
  ./scripts/verify-secret-boundaries.sh
  backend/scripts/validate-env.sh local backend/.env.local.example
  backend/scripts/validate-env.sh production backend/.env.production.example
  apps/ios/scripts/validate-env.zsh \
    --kind local --example-only apps/ios/.env.local.example
  apps/ios/scripts/validate-env.zsh \
    --kind production --example-only apps/ios/.env.production.example
  git diff --check
  git diff --cached --check

  for env_path in "${env_paths[@]}"; do
    if [[ ! -e "$env_path" ]]; then
      continue
    fi
    git check-ignore --quiet -- "$env_path" || {
      printf 'ERROR: actual environment file is not ignored: %s\n' "$env_path" >&2
      return 1
    }
    mode=$(file_mode "$env_path")
    if [[ "$mode" != 600 ]]; then
      printf 'ERROR: actual environment file must have mode 0600: %s\n' "$env_path" >&2
      return 1
    fi
  done

  printf 'Delivery preflight passed.\n'
}

run_backend() {
  cd "$repo_root/backend"
  ./gradlew --no-daemon check bootJar
  printf 'Backend delivery gate passed.\n'
}

run_local_smoke() (
  local suffix network_name database_container api_container image_tag published_port response_dir=''
  local database_ready=false api_ready=false
  local invalid_actor=invalid-slot invalid_pin=0000

  require_command docker
  require_command curl
  suffix="$$-$(date +%s)"
  network_name="woorisai-delivery-${suffix}"
  database_container="woorisai-postgres-${suffix}"
  api_container="woorisai-api-${suffix}"
  image_tag="woorisai:delivery-${suffix}"

  # shellcheck disable=SC2317  # Invoked by EXIT/interrupt traps.
  cleanup_local_smoke() {
    set +e
    [[ -z "$response_dir" ]] || rm -rf -- "$response_dir"
    docker rm --force "$api_container" "$database_container" >/dev/null 2>&1
    docker network rm "$network_name" >/dev/null 2>&1
    docker image rm "$image_tag" >/dev/null 2>&1
  }
  trap cleanup_local_smoke EXIT INT TERM

  cd "$repo_root"
  docker network create "$network_name" >/dev/null
  docker run --detach \
    --name "$database_container" \
    --network "$network_name" \
    --env POSTGRES_DB=woorisai \
    --env POSTGRES_USER=woorisai_local \
    --env POSTGRES_PASSWORD=woorisai_local \
    --health-cmd 'pg_isready -U woorisai_local -d woorisai' \
    --health-interval 2s \
    --health-timeout 5s \
    --health-retries 30 \
    postgres:18.4-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15 \
    >/dev/null

  for _attempt in $(seq 1 60); do
    if [[ "$(docker inspect --format '{{.State.Health.Status}}' "$database_container")" == healthy ]]; then
      database_ready=true
      break
    fi
    sleep 2
  done
  if [[ "$database_ready" != true ]]; then
    docker logs "$database_container" >&2
    printf 'ERROR: local PostgreSQL did not become healthy.\n' >&2
    return 1
  fi

  docker build --pull --tag "$image_tag" .
  if [[ "$(docker image inspect --format '{{.Config.User}}' "$image_tag")" != 10001:10001 ]]; then
    printf 'ERROR: local image runtime user is not 10001:10001.\n' >&2
    return 1
  fi

  docker run --detach \
    --name "$api_container" \
    --network "$network_name" \
    --publish 127.0.0.1::8080 \
    --env PORT=8080 \
    --env "SPRING_DATASOURCE_URL=jdbc:postgresql://${database_container}:5432/woorisai" \
    --env SPRING_DATASOURCE_USERNAME=woorisai_local \
    --env SPRING_DATASOURCE_PASSWORD=woorisai_local \
    "$image_tag" \
    >/dev/null
  published_port=$(docker port "$api_container" 8080/tcp | awk -F: '/127[.]0[.]0[.]1/ {print $NF; exit}')
  if [[ ! "$published_port" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: local API port could not be resolved.\n' >&2
    return 1
  fi

  for _attempt in $(seq 1 60); do
    if curl --fail --silent \
      "http://127.0.0.1:${published_port}/health" >/dev/null 2>&1; then
      api_ready=true
      break
    fi
    sleep 2
  done
  if [[ "$api_ready" != true ]]; then
    docker logs "$api_container" >&2
    printf 'ERROR: local API did not become ready.\n' >&2
    return 1
  fi

  docker exec "$database_container" \
    psql --username woorisai_local --dbname woorisai \
    --set ON_ERROR_STOP=1 \
    --command \
    "INSERT INTO woorisai.participant (slot, display_name, created_at) VALUES
      (1, 'Synthetic Participant A', CURRENT_TIMESTAMP),
      (2, 'Synthetic Participant B', CURRENT_TIMESTAMP);" \
    >/dev/null

  local login_status protected_status
  response_dir=$(mktemp -d)
  login_status=$(curl --silent --show-error \
    --output "${response_dir}/login-options" \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${published_port}/api/v2/auth/login-options")
  protected_status=$(curl --silent --show-error \
    --user "${invalid_actor}:${invalid_pin}" \
    --dump-header "${response_dir}/protected-headers" \
    --output "${response_dir}/protected-body" \
    --write-out '%{http_code}' \
    "http://127.0.0.1:${published_port}/api/v2/relationship-scores")
  if [[ "$login_status" != 200 || "$protected_status" != 401 ]] || \
    ! grep --ignore-case --quiet '^cache-control:.*no-store' \
      "${response_dir}/protected-headers"; then
    rm -rf -- "$response_dir"
    printf 'ERROR: local API boundary smoke failed.\n' >&2
    return 1
  fi
  rm -rf -- "$response_dir"
  response_dir=''

  printf 'Local container deployment smoke passed.\n'
)

run_ios() (
  local runtime iphone_15_id='' iphone_13_id='' derived_data_root

  require_command xcodebuild
  require_command xcrun
  runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-5'
  mkdir -p "$repo_root/.local"
  derived_data_root=$(mktemp -d "$repo_root/.local/delivery-ios.XXXXXX")

  # shellcheck disable=SC2317  # Invoked by EXIT/interrupt traps.
  cleanup_ios() {
    set +e
    [[ -z "$iphone_15_id" ]] || xcrun simctl delete "$iphone_15_id" >/dev/null 2>&1
    [[ -z "$iphone_13_id" ]] || xcrun simctl delete "$iphone_13_id" >/dev/null 2>&1
    rm -rf -- "$derived_data_root"
  }
  trap cleanup_ios EXIT INT TERM

  cd "$repo_root"
  xcodebuild -version | grep --fixed-strings --line-regexp 'Xcode 26.6'
  xcodebuild -version | grep --fixed-strings --line-regexp 'Build version 17F113'
  xcodebuild -resolvePackageDependencies \
    -project apps/ios/Woorisai.xcodeproj \
    -scheme Woorisai \
    -clonedSourcePackagesDirPath "${derived_data_root}/source-packages" \
    -onlyUsePackageVersionsFromResolvedFile

  iphone_15_id=$(xcrun simctl create \
    "Woorisai Local iPhone 15 Pro $$" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro \
    "$runtime")
  iphone_13_id=$(xcrun simctl create \
    "Woorisai Local iPhone 13 Pro $$" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro \
    "$runtime")

  xcodebuild build-for-testing \
    -project apps/ios/Woorisai.xcodeproj \
    -scheme Woorisai \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${iphone_15_id}" \
    -derivedDataPath "${derived_data_root}/debug" \
    -clonedSourcePackagesDirPath "${derived_data_root}/source-packages" \
    -enableCodeCoverage NO \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO
  xcodebuild test-without-building \
    -project apps/ios/Woorisai.xcodeproj \
    -scheme Woorisai \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${iphone_15_id}" \
    -derivedDataPath "${derived_data_root}/debug" \
    -clonedSourcePackagesDirPath "${derived_data_root}/source-packages" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 600 \
    -enableCodeCoverage NO \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO
  xcodebuild test-without-building \
    -project apps/ios/Woorisai.xcodeproj \
    -scheme Woorisai \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${iphone_13_id}" \
    -derivedDataPath "${derived_data_root}/debug" \
    -clonedSourcePackagesDirPath "${derived_data_root}/source-packages" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 600 \
    -enableCodeCoverage NO \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO
  xcodebuild build \
    -project apps/ios/Woorisai.xcodeproj \
    -scheme Woorisai \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${derived_data_root}/release" \
    -clonedSourcePackagesDirPath "${derived_data_root}/source-packages" \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

  printf 'iOS delivery gates passed.\n'
)

main() {
  local command_name=${1:-}

  if (( $# != 1 )); then
    usage >&2
    return 2
  fi
  case "$command_name" in
    preflight)
      run_preflight
      ;;
    backend)
      run_backend
      ;;
    local-smoke)
      run_local_smoke
      ;;
    ios)
      run_ios
      ;;
    all)
      run_preflight
      run_backend
      run_local_smoke
      run_ios
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
