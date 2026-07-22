#!/bin/zsh

setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset -gr release_script_dir="${0:A:h}"
typeset -gr release_ios_dir="${release_script_dir:h}"
typeset -gr release_project_path="${release_ios_dir}/Woorisai.xcodeproj"
typeset -gr release_scheme=Woorisai
typeset -gr release_bundle_identifier=com.naminhyeok.woorisai
typeset -g release_temp_dir=""

# This sources executable parser code, never a dotenv file. The parser treats dotenv input as data.
source "${release_script_dir}/validate-env.zsh"

release_log() {
  print -- "$1"
}

release_fail() {
  print -u2 -- "error: $1"
  exit 1
}

release_usage() {
  print -u2 -- \
    "usage: release-testflight.zsh [--env-file PATH] [--build-number NUMBER] [--marketing-version VERSION] [--no-upload]"
}

release_cleanup() {
  unset WOORISAI_FIREBASE_RELEASE_CONFIG_PATH 2>/dev/null || true
  unset WOORISAI_FIREBASE_RELEASE_REALM_SHA256 2>/dev/null || true
  unset WOORISAI_FIREBASE_DEBUG_REALM_SHA256 2>/dev/null || true
  unset API_PRIVATE_KEYS_DIR 2>/dev/null || true
  if [[ -n "${release_temp_dir:-}" && -d "$release_temp_dir" ]]; then
    /bin/rm -rf -- "$release_temp_dir"
  fi
}

trap release_cleanup EXIT
trap 'exit 130' HUP INT TERM

release_verify_toolchain() {
  local -a version_lines

  version_lines=("${(@f)$(/usr/bin/xcodebuild -version)}")
  if (( ${#version_lines[@]} < 2 )) || \
    [[ "${version_lines[1]}" != "Xcode 26.6" ]] || \
    [[ "${version_lines[2]}" != "Build version 17F113" ]]; then
    release_fail "Xcode 26.6 build 17F113 must be selected"
  fi
  if ! /usr/bin/xcrun --find altool >/dev/null 2>&1; then
    release_fail "the selected Xcode does not provide altool"
  fi
}

release_create_export_options() {
  local export_options_path="$1"
  local extracted_value

  /usr/bin/plutil -create xml1 "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :method string app-store-connect" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :destination string export" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :manageAppVersionAndBuildNumber bool false" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :uploadSymbols bool true" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :testFlightInternalTestingOnly bool false" "$export_options_path"
  /usr/bin/plutil -lint "$export_options_path" >/dev/null

  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :method" "$export_options_path")"
  [[ "$extracted_value" == app-store-connect ]] || release_fail "invalid export method"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :destination" "$export_options_path")"
  [[ "$extracted_value" == export ]] || release_fail "invalid export destination"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :signingStyle" "$export_options_path")"
  [[ "$extracted_value" == automatic ]] || release_fail "invalid export signing style"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :manageAppVersionAndBuildNumber" "$export_options_path")"
  [[ "$extracted_value" == false ]] || release_fail "Xcode-managed build numbering must be disabled"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :uploadSymbols" "$export_options_path")"
  [[ "$extracted_value" == true ]] || release_fail "symbol upload must be enabled"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :testFlightInternalTestingOnly" "$export_options_path")"
  [[ "$extracted_value" == false ]] || release_fail "the exported build must remain App Store promotable"
}

release_resolve_packages() {
  release_log "Resolving exact Swift package versions."
  /usr/bin/xcodebuild -resolvePackageDependencies \
    -project "$release_project_path" \
    -scheme "$release_scheme" \
    -onlyUsePackageVersionsFromResolvedFile \
    -hideShellScriptEnvironment \
    -quiet
}

release_environment_has_placeholders() {
  local key

  for key in "${WOORISAI_ENV_KEYS[@]}"; do
    if woorisai_env_value_is_placeholder "${WOORISAI_ENV_VALUES[$key]}"; then
      return 0
    fi
  done
  return 1
}

release_plist_value() {
  local plist_path="$1"
  local key="$2"
  local output

  if ! output="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null)"; then
    return 1
  fi
  print -r -- "$output"
}

release_verify_firebase_configuration() {
  local app_path="$1"
  local firebase_path="${app_path}/GoogleService-Info.plist"
  local firebase_bundle_id firebase_google_app_id firebase_project_id firebase_api_key
  local firebase_sender_id firebase_actual_digest

  if [[ ! -f "$firebase_path" ]] || ! /usr/bin/plutil -lint "$firebase_path" >/dev/null 2>&1; then
    release_fail "the app is missing a valid Firebase Apple client configuration"
  fi
  if ! firebase_bundle_id="$(release_plist_value "$firebase_path" BUNDLE_ID)" || \
    ! firebase_google_app_id="$(release_plist_value "$firebase_path" GOOGLE_APP_ID)" || \
    ! firebase_project_id="$(release_plist_value "$firebase_path" PROJECT_ID)" || \
    ! firebase_api_key="$(release_plist_value "$firebase_path" API_KEY)" || \
    ! firebase_sender_id="$(release_plist_value "$firebase_path" GCM_SENDER_ID)"; then
    release_fail "the embedded Firebase Apple client configuration is incomplete"
  fi
  if [[ "$firebase_bundle_id" != "$release_bundle_identifier" ]] || \
    [[ -z "$firebase_google_app_id" || -z "$firebase_project_id" || \
      -z "$firebase_api_key" || -z "$firebase_sender_id" ]]; then
    release_fail "the embedded Firebase Apple client configuration is not valid for the app"
  fi

  firebase_actual_digest=$(
    /usr/bin/printf '%s\0%s\0%s\0%s\0%s\0' \
      "$firebase_project_id" "$firebase_google_app_id" "$firebase_sender_id" \
      "$firebase_api_key" "$firebase_bundle_id" \
      | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  )
  if [[ "$firebase_actual_digest" != \
    "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_REALM_SHA256]:l}" ]]; then
    release_fail "the embedded Firebase realm does not match the approved release assertion"
  fi
}

release_verify_app_bundle() {
  local app_path="$1"
  local expected_marketing_version="$2"
  local expected_build_number="$3"
  local info_path="${app_path}/Info.plist"
  local entitlements_path="${release_temp_dir}/entitlements-$RANDOM.plist"
  local signature_log="${release_temp_dir}/codesign-$RANDOM.log"
  local bundle_id marketing_version build_number api_host aps_environment get_task_allow
  local forbidden_path

  if [[ ! -d "$app_path" || ! -f "$info_path" ]]; then
    release_fail "the release application bundle is missing"
  fi
  if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" \
    >"$signature_log" 2>&1; then
    release_fail "release code signature verification failed"
  fi
  if ! /usr/bin/codesign -d --entitlements :- "$app_path" \
    >"$entitlements_path" 2>"$signature_log"; then
    release_fail "release entitlements could not be inspected"
  fi
  if ! /usr/bin/plutil -lint "$entitlements_path" >/dev/null 2>&1; then
    release_fail "release entitlements are malformed"
  fi

  if ! bundle_id="$(release_plist_value "$info_path" CFBundleIdentifier)" || \
    ! marketing_version="$(release_plist_value "$info_path" CFBundleShortVersionString)" || \
    ! build_number="$(release_plist_value "$info_path" CFBundleVersion)" || \
    ! api_host="$(release_plist_value "$info_path" WoorisaiAPIHost)"; then
    release_fail "release bundle identity is incomplete"
  fi
  if [[ "$bundle_id" != "$release_bundle_identifier" ]] || \
    [[ "$marketing_version" != "$expected_marketing_version" ]] || \
    [[ "$build_number" != "$expected_build_number" ]]; then
    release_fail "release bundle identity does not match the requested release"
  fi
  if [[ "$api_host" != "${WOORISAI_ENV_VALUES[WOORISAI_API_HOST]}" ]]; then
    release_fail "release API host does not match the approved production target"
  fi

  if ! aps_environment="$(release_plist_value "$entitlements_path" aps-environment)" || \
    [[ "$aps_environment" != production ]]; then
    release_fail "release Push Notifications entitlement is not production"
  fi
  if get_task_allow="$(release_plist_value "$entitlements_path" get-task-allow)"; then
    if [[ "$get_task_allow" != false ]]; then
      release_fail "release get-task-allow entitlement must be false"
    fi
  fi
  if [[ ! -f "${app_path}/embedded.mobileprovision" ]]; then
    release_fail "release provisioning profile is missing"
  fi

  forbidden_path="$(/usr/bin/find "$app_path" -type f \
    \( -name '.env' -o -name '.env.*' -o -name '*.p8' -o -name '*.p12' \
    -o -name 'firebase-service-account*.json' \) -print -quit)"
  if [[ -n "$forbidden_path" ]]; then
    release_fail "the app bundle contains a forbidden credential file"
  fi
  release_verify_firebase_configuration "$app_path"
}

release_prepare_authentication_key() {
  local private_key_dir="$1"
  local destination_path="${private_key_dir}/AuthKey_${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}.p8"

  /bin/mkdir -p "$private_key_dir"
  /bin/cp "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_PATH]}" "$destination_path"
  /bin/chmod 600 "$destination_path"
  print -r -- "$destination_path"
}

release_archive_and_export() {
  local marketing_version="$1"
  local build_number="$2"
  local export_options_path="$3"
  local should_upload="$4"
  local archive_path="${release_temp_dir}/Woorisai.xcarchive"
  local derived_data_path="${release_temp_dir}/DerivedData"
  local export_path="${release_temp_dir}/export"
  local unpacked_path="${release_temp_dir}/unpacked"
  local private_key_dir="${release_temp_dir}/private_keys"
  local authentication_key_path
  local archive_app_path="${archive_path}/Products/Applications/Woorisai.app"
  local -a ipa_files exported_apps
  local ipa_path exported_app_path
  local validation_log="${release_temp_dir}/altool-validate.log"
  local upload_log="${release_temp_dir}/altool-upload.log"

  authentication_key_path="$(release_prepare_authentication_key "$private_key_dir")"
  export API_PRIVATE_KEYS_DIR="$private_key_dir"
  export WOORISAI_FIREBASE_RELEASE_CONFIG_PATH="${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_CONFIG_PATH]}"
  export WOORISAI_FIREBASE_RELEASE_REALM_SHA256="${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_REALM_SHA256]}"
  export WOORISAI_FIREBASE_DEBUG_REALM_SHA256="${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_DEBUG_REALM_SHA256]}"

  release_log "Creating the signed Release archive."
  /usr/bin/xcodebuild archive \
    -project "$release_project_path" \
    -scheme "$release_scheme" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation \
    -hideShellScriptEnvironment \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$authentication_key_path" \
    -authenticationKeyID "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" \
    -authenticationKeyIssuerID "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" \
    CODE_SIGN_STYLE=Automatic \
    MARKETING_VERSION="$marketing_version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    WOORISAI_API_HOST="${WOORISAI_ENV_VALUES[WOORISAI_API_HOST]}" \
    -quiet

  release_verify_app_bundle "$archive_app_path" "$marketing_version" "$build_number"

  release_log "Exporting an App Store Connect IPA from the verified archive."
  /usr/bin/xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options_path" \
    -hideShellScriptEnvironment \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$authentication_key_path" \
    -authenticationKeyID "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" \
    -authenticationKeyIssuerID "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" \
    -quiet

  ipa_files=("$export_path"/*.ipa(N))
  if (( ${#ipa_files[@]} != 1 )); then
    release_fail "the export must produce exactly one IPA"
  fi
  ipa_path="${ipa_files[1]}"
  /usr/bin/ditto -x -k "$ipa_path" "$unpacked_path"
  exported_apps=("$unpacked_path"/Payload/*.app(N/))
  if (( ${#exported_apps[@]} != 1 )); then
    release_fail "the IPA must contain exactly one application bundle"
  fi
  exported_app_path="${exported_apps[1]}"
  release_verify_app_bundle "$exported_app_path" "$marketing_version" "$build_number"

  release_log "Validating the IPA with App Store Connect."
  if ! /usr/bin/xcrun altool --validate-app -f "$ipa_path" -t ios \
    --api-key "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" \
    --api-issuer "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" \
    --output-format json >"$validation_log" 2>&1; then
    release_fail "App Store Connect IPA validation failed; provider output was suppressed"
  fi

  if [[ "$should_upload" == true ]]; then
    release_log "Uploading the validated IPA and waiting for App Store Connect processing."
    if ! /usr/bin/xcrun altool --upload-package "$ipa_path" \
      --api-key "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" \
      --api-issuer "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" \
      --wait --output-format json >"$upload_log" 2>&1; then
      release_fail "App Store Connect upload or processing failed; provider output was suppressed"
    fi
    release_log "TestFlight upload and processing completed."
  else
    release_log "Signed IPA validation completed; upload was skipped."
  fi
}

release_main() {
  local env_file="${release_ios_dir}/.env.production"
  local build_number_override=""
  local marketing_version_override=""
  local no_upload=false
  local static_only=false
  local export_options_path
  local marketing_version build_number

  while (( $# > 0 )); do
    case "$1" in
      --env-file)
        (( $# >= 2 )) || { release_usage; return 2; }
        env_file="$2"
        shift 2
        ;;
      --build-number)
        (( $# >= 2 )) || { release_usage; return 2; }
        build_number_override="$2"
        shift 2
        ;;
      --marketing-version)
        (( $# >= 2 )) || { release_usage; return 2; }
        marketing_version_override="$2"
        shift 2
        ;;
      --no-upload)
        no_upload=true
        shift
        ;;
      --help|-h)
        release_usage
        return 0
        ;;
      *)
        release_usage
        return 2
        ;;
    esac
  done

  woorisai_parse_env production "$env_file" schema || return 1
  if [[ -n "$marketing_version_override" ]]; then
    woorisai_validate_marketing_version "$marketing_version_override" || return 1
    WOORISAI_ENV_VALUES[IOS_MARKETING_VERSION]="$marketing_version_override"
  fi
  if [[ -n "$build_number_override" ]]; then
    woorisai_validate_build_number "$build_number_override" || return 1
    WOORISAI_ENV_VALUES[IOS_BUILD_NUMBER]="$build_number_override"
  fi

  if [[ "$no_upload" == true ]] && release_environment_has_placeholders; then
    static_only=true
  else
    woorisai_validate_loaded_values production || return 1
  fi

  release_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/woorisai-ios-release.XXXXXXXX")"
  export_options_path="${release_temp_dir}/ExportOptions.plist"
  release_verify_toolchain
  release_create_export_options "$export_options_path"
  release_resolve_packages

  if [[ "$static_only" == true ]]; then
    release_log "Static release validation completed; archive and upload were skipped."
    return 0
  fi

  marketing_version="${WOORISAI_ENV_VALUES[IOS_MARKETING_VERSION]}"
  build_number="${WOORISAI_ENV_VALUES[IOS_BUILD_NUMBER]}"
  if [[ "$no_upload" == true ]]; then
    release_archive_and_export "$marketing_version" "$build_number" "$export_options_path" false
  else
    release_archive_and_export "$marketing_version" "$build_number" "$export_options_path" true
  fi
}

release_main "$@"
