#!/bin/zsh

setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset -gr release_script_dir="${0:A:h}"
typeset -gr release_ios_dir="${release_script_dir:h}"
typeset -gr release_project_path="${release_ios_dir}/Woorisai.xcodeproj"
typeset -gr release_scheme=Woorisai
typeset -gr release_bundle_identifier=com.naminhyeok.woorisai
typeset -gr release_signing_team_id=83KHWR8L3R
typeset -gr release_signing_certificate_name='Apple Distribution'
typeset -gr release_provisioning_profile_name='Woorisai App Store Reusable 2026'
typeset -g release_temp_dir=""
typeset -g release_evidence_path=""
typeset -g release_distribution_p12_path=""
typeset -g release_distribution_p12_password_path=""
typeset -g release_provisioning_profile_path=""
typeset -g release_signing_keychain_path=""
typeset -g release_signing_keychain_created=false
typeset -g release_keychain_search_changed=false
typeset -g release_original_default_keychain=""
typeset -ga release_original_keychain_search=()
typeset -g release_signing_identity_sha1=""
typeset -g release_profile_uuid=""
typeset -g release_profile_sha256=""
typeset -g release_installed_profile_path=""
typeset -g release_installed_profile_owned=false
typeset -g release_beta_group=""
typeset -gr release_ascapi_base="https://api.appstoreconnect.apple.com"

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
    "usage: release-testflight.zsh [--env-file PATH] [--build-number NUMBER] [--marketing-version VERSION] [--evidence-file ABSOLUTE_PATH] [--beta-group NAME] [--distribution-p12 PATH --distribution-p12-password-file PATH --provisioning-profile PATH] [--no-upload]"
}

release_cleanup_signing() {
  local cleanup_failed=false

  if [[ "$release_installed_profile_owned" == true ]]; then
    if [[ -n "$release_installed_profile_path" && \
      -f "$release_installed_profile_path" && ! -L "$release_installed_profile_path" ]]; then
      /bin/rm -f -- "$release_installed_profile_path" || cleanup_failed=true
    elif [[ -n "$release_installed_profile_path" ]]; then
      cleanup_failed=true
    fi
  fi

  if [[ "$release_keychain_search_changed" == true ]]; then
    if (( ${#release_original_keychain_search[@]} > 0 )); then
      /usr/bin/security list-keychains -d user -s \
        "${release_original_keychain_search[@]}" >/dev/null 2>&1 || cleanup_failed=true
    fi
    if [[ -n "$release_original_default_keychain" ]]; then
      /usr/bin/security default-keychain -d user -s \
        "$release_original_default_keychain" >/dev/null 2>&1 || cleanup_failed=true
    fi
  fi

  if [[ "$release_signing_keychain_created" == true && \
    -n "$release_signing_keychain_path" ]]; then
    /usr/bin/security delete-keychain \
      "$release_signing_keychain_path" >/dev/null 2>&1 || cleanup_failed=true
  fi

  release_installed_profile_owned=false
  release_installed_profile_path=""
  release_keychain_search_changed=false
  release_signing_keychain_created=false
  release_signing_keychain_path=""
  release_signing_identity_sha1=""

  [[ "$cleanup_failed" == false ]]
}

release_cleanup() {
  local cleanup_failed=false

  unset WOORISAI_FIREBASE_RELEASE_CONFIG_PATH 2>/dev/null || true
  unset WOORISAI_FIREBASE_RELEASE_REALM_SHA256 2>/dev/null || true
  unset WOORISAI_FIREBASE_DEBUG_REALM_SHA256 2>/dev/null || true
  unset API_PRIVATE_KEYS_DIR 2>/dev/null || true
  release_cleanup_signing || cleanup_failed=true
  if [[ -n "${release_temp_dir:-}" && -d "$release_temp_dir" ]]; then
    /bin/rm -rf -- "$release_temp_dir" || cleanup_failed=true
  fi
  [[ "$cleanup_failed" == false ]]
}

release_exit_handler() {
  local release_status=$?

  trap - EXIT ZERR HUP INT TERM
  setopt NO_ERR_EXIT
  if ! release_cleanup; then
    print -u2 -- "error: temporary release credential cleanup failed"
    if (( release_status == 0 )); then
      release_status=1
    fi
  fi
  exit "$release_status"
}

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

release_validate_private_input_file() {
  local input_path="$1"
  local input_label="$2"
  local required_suffix="$3"
  local input_mode

  if [[ "$input_path" != /* || ! -f "$input_path" || ! -r "$input_path" || \
    -L "$input_path" ]]; then
    release_fail "$input_label must be an absolute, readable regular file"
  fi
  if [[ -n "$required_suffix" && "$input_path" != *"$required_suffix" ]]; then
    release_fail "$input_label must reference a $required_suffix file"
  fi
  input_mode="$(/usr/bin/stat -f '%Lp' "$input_path")"
  if [[ ! "$input_mode" =~ '^[0-7]{3,4}$' ]] || \
    (( (8#$input_mode & 8#77) != 0 )); then
    release_fail "$input_label must not be readable or writable by group or other users"
  fi
}

release_validate_signing_inputs() {
  local -i configured_count=0
  local password_line_count password_size

  [[ -n "$release_distribution_p12_path" ]] && (( configured_count += 1 ))
  [[ -n "$release_distribution_p12_password_path" ]] && (( configured_count += 1 ))
  [[ -n "$release_provisioning_profile_path" ]] && (( configured_count += 1 ))

  if (( configured_count != 0 && configured_count != 3 )); then
    release_fail "distribution certificate, password file, and provisioning profile must be provided together"
  fi
  if (( configured_count == 0 )); then
    release_fail "manual App Store distribution signing inputs are required"
  fi

  release_validate_private_input_file \
    "$release_distribution_p12_path" "the distribution certificate" .p12
  release_validate_private_input_file \
    "$release_distribution_p12_password_path" "the distribution certificate password file" ""
  release_validate_private_input_file \
    "$release_provisioning_profile_path" "the provisioning profile" .mobileprovision

  password_size="$(/usr/bin/stat -f '%z' "$release_distribution_p12_password_path")"
  password_line_count="$(/usr/bin/awk 'END { print NR }' \
    "$release_distribution_p12_password_path")"
  if (( password_size < 1 || password_size > 1024 || password_line_count != 1 )) || \
    LC_ALL=C /usr/bin/grep -q $'\r' "$release_distribution_p12_password_path"; then
    release_fail "the distribution certificate password file must contain one bounded line"
  fi
}

release_signing_inputs_configured() {
  [[ -n "$release_distribution_p12_path" || \
    -n "$release_distribution_p12_password_path" || \
    -n "$release_provisioning_profile_path" ]]
}

release_sha256_file() {
  local file_path="$1"
  local digest
  local digest_re='^[0-9a-f]{64}$'

  if [[ ! -f "$file_path" || -L "$file_path" ]]; then
    release_fail "the SHA-256 input must be a regular file"
  fi
  digest="$(/usr/bin/shasum -a 256 -- "$file_path" | /usr/bin/awk '{print $1}')"
  if [[ ! "$digest" =~ $digest_re ]]; then
    release_fail "a SHA-256 digest could not be computed"
  fi
  print -r -- "$digest"
}

release_archive_tree_sha256() {
  local archive_path="$1"
  local manifest_path="${release_temp_dir}/archive-manifest-$RANDOM"
  local entry relative_path entry_type entry_mode entry_value
  local digest
  local -a entries
  local LC_ALL=C

  if [[ ! -d "$archive_path" || -L "$archive_path" ]]; then
    release_fail "the archive checksum input must be a directory"
  fi

  entries=("$archive_path"/**/*(DN))
  entries=("${(@on)entries}")
  : >| "$manifest_path"
  entry_mode="$(/usr/bin/stat -f '%Lp' "$archive_path")"
  /usr/bin/printf 'D\0.\0%s\0' "$entry_mode" >>"$manifest_path"

  for entry in "${entries[@]}"; do
    relative_path="${entry#$archive_path/}"
    entry_mode="$(/usr/bin/stat -f '%Lp' "$entry")"
    if [[ -L "$entry" ]]; then
      entry_type=L
      entry_value="$(/usr/bin/readlink "$entry")"
    elif [[ -d "$entry" ]]; then
      entry_type=D
      entry_value=""
    elif [[ -f "$entry" ]]; then
      entry_type=F
      entry_value="$(release_sha256_file "$entry")"
    else
      release_fail "the archive contains an unsupported filesystem entry"
    fi
    /usr/bin/printf '%s\0%s\0%s\0%s\0' \
      "$entry_type" "$relative_path" "$entry_mode" "$entry_value" >>"$manifest_path"
  done

  digest="$(release_sha256_file "$manifest_path")"
  /bin/rm -f -- "$manifest_path"
  print -r -- "$digest"
}

release_source_revision() {
  local revision
  local revision_re='^[0-9a-f]{40}$'

  if ! revision="$(/usr/bin/git -C "$release_ios_dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || \
    [[ ! "$revision" =~ $revision_re ]]; then
    release_fail "the release source revision could not be resolved"
  fi
  print -r -- "$revision"
}

release_verify_upload_source_clean() {
  local repository_path="${1:-$release_ios_dir}"
  local status_log="${release_temp_dir}/upload-source-status-$RANDOM.log"

  if ! /usr/bin/git -C "$repository_path" status \
    --porcelain=v1 \
    --untracked-files=all >"$status_log" 2>&1; then
    /bin/rm -f -- "$status_log"
    release_fail "the release source worktree could not be inspected"
  fi
  if [[ -s "$status_log" ]]; then
    /bin/rm -f -- "$status_log"
    release_fail "a real TestFlight upload requires a clean source worktree"
  fi
  /bin/rm -f -- "$status_log"
}

release_extract_app_store_build_identifier() {
  local upload_log="$1"
  local response_plist="${release_temp_dir}/altool-upload-response-$RANDOM.plist"
  local response_type identifier
  local identifier_re='^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'

  if [[ ! -s "$upload_log" ]] || \
    ! /usr/bin/plutil -convert xml1 -o "$response_plist" "$upload_log" >/dev/null 2>&1; then
    return 1
  fi
  if ! response_type="$(release_plist_value "$response_plist" 'data:type')" || \
    ! identifier="$(release_plist_value "$response_plist" 'data:id')"; then
    /bin/rm -f -- "$response_plist"
    return 1
  fi
  /bin/rm -f -- "$response_plist"

  if [[ "$response_type" != builds ]] || \
    [[ ! "$identifier" =~ $identifier_re ]]; then
    return 1
  fi
  print -r -- "$identifier"
}

release_verify_evidence_destination() {
  local evidence_probe_path=""

  if [[ -z "$release_evidence_path" ]]; then
    return 0
  fi
  if [[ "$release_evidence_path" != /* || ! -d "${release_evidence_path:h}" ]]; then
    release_fail "the release evidence path must be absolute and its parent directory must exist"
  fi
  if [[ -e "$release_evidence_path" && \
    ( ! -f "$release_evidence_path" || ! -w "$release_evidence_path" ) ]]; then
    release_fail "the release evidence path must be a writable regular file"
  fi
  if ! evidence_probe_path="$(/usr/bin/mktemp "${release_evidence_path}.probe.XXXXXX")"; then
    release_fail "the release evidence destination is not writable"
  fi
  /bin/chmod 600 "$evidence_probe_path"
  /bin/rm -f -- "$evidence_probe_path"
}

release_write_evidence() {
  local source_revision="$1"
  local marketing_version="$2"
  local build_number="$3"
  local archive_tree_sha256="$4"
  local ipa_sha256="$5"
  local validation_status="$6"
  local upload_status="$7"
  local app_store_build_identifier="$8"
  local evidence_temp_path=""
  local key value
  local -a evidence_lines
  local revision_re='^[0-9a-f]{40}$'
  local digest_re='^[0-9a-f]{64}$'
  local build_identifier_re='^([A-Za-z0-9][A-Za-z0-9._:-]{0,127}|not-applicable|not-reported)$'

  evidence_lines=(
    "evidence_format_version=1"
    "source_revision=$source_revision"
    "bundle_identifier=$release_bundle_identifier"
    "marketing_version=$marketing_version"
    "build_number=$build_number"
    "archive_tree_sha256=$archive_tree_sha256"
    "ipa_sha256=$ipa_sha256"
    "validation_status=$validation_status"
    "upload_status=$upload_status"
    "app_store_build_identifier=$app_store_build_identifier"
  )

  [[ "$source_revision" =~ $revision_re ]] || \
    release_fail "release evidence contains an invalid source revision"
  woorisai_validate_marketing_version "$marketing_version" || \
    release_fail "release evidence contains an invalid marketing version"
  woorisai_validate_build_number "$build_number" || \
    release_fail "release evidence contains an invalid build number"
  [[ "$archive_tree_sha256" =~ $digest_re ]] || \
    release_fail "release evidence contains an invalid archive checksum"
  [[ "$ipa_sha256" =~ $digest_re ]] || \
    release_fail "release evidence contains an invalid IPA checksum"
  [[ "$validation_status" == succeeded ]] || \
    release_fail "release evidence contains an invalid validation status"
  [[ "$upload_status" == succeeded || "$upload_status" == skipped ]] || \
    release_fail "release evidence contains an invalid upload status"
  [[ "$app_store_build_identifier" =~ $build_identifier_re ]] || \
    release_fail "release evidence contains an invalid App Store build identifier"

  release_log "Release evidence:"
  for key in "${evidence_lines[@]}"; do
    release_log "  $key"
  done

  if [[ -z "$release_evidence_path" ]]; then
    return 0
  fi
  release_verify_evidence_destination

  evidence_temp_path="$(/usr/bin/mktemp "${release_evidence_path}.tmp.XXXXXX")"
  : >| "$evidence_temp_path"
  for value in "${evidence_lines[@]}"; do
    print -r -- "$value" >>"$evidence_temp_path"
  done
  /bin/chmod 600 "$evidence_temp_path"
  /bin/mv -f -- "$evidence_temp_path" "$release_evidence_path"
}

release_create_export_options() {
  local export_options_path="$1"
  local extracted_value

  /usr/bin/plutil -create xml1 "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :method string app-store-connect" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :destination string export" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :signingStyle string manual" "$export_options_path"
  /usr/libexec/PlistBuddy -c \
    "Add :signingCertificate string $release_signing_certificate_name" \
    "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :teamID string $release_signing_team_id" \
    "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "$export_options_path"
  /usr/libexec/PlistBuddy -c \
    "Add :provisioningProfiles:$release_bundle_identifier string $release_provisioning_profile_name" \
    "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :manageAppVersionAndBuildNumber bool false" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :uploadSymbols bool true" "$export_options_path"
  /usr/libexec/PlistBuddy -c "Add :testFlightInternalTestingOnly bool false" "$export_options_path"
  /usr/bin/plutil -lint "$export_options_path" >/dev/null

  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :method" "$export_options_path")"
  [[ "$extracted_value" == app-store-connect ]] || release_fail "invalid export method"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :destination" "$export_options_path")"
  [[ "$extracted_value" == export ]] || release_fail "invalid export destination"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :signingStyle" "$export_options_path")"
  [[ "$extracted_value" == manual ]] || release_fail "invalid export signing style"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :signingCertificate" "$export_options_path")"
  [[ "$extracted_value" == "$release_signing_certificate_name" ]] || \
    release_fail "invalid export signing certificate"
  extracted_value="$(/usr/libexec/PlistBuddy -c "Print :teamID" "$export_options_path")"
  [[ "$extracted_value" == "$release_signing_team_id" ]] || \
    release_fail "invalid export signing team"
  extracted_value="$(/usr/libexec/PlistBuddy -c \
    "Print :provisioningProfiles:$release_bundle_identifier" "$export_options_path")"
  [[ "$extracted_value" == "$release_provisioning_profile_name" ]] || \
    release_fail "invalid export provisioning profile"
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

release_keychain_path_from_security_output() {
  local keychain_line="$1"

  keychain_line="$(print -r -- "$keychain_line" | \
    /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
  [[ -n "$keychain_line" ]] || release_fail "the current keychain configuration is malformed"
  print -r -- "$keychain_line"
}

release_prepare_signing_keychain() {
  local keychain_password signing_pem_path security_log identity_log identity_hash
  local keychain_line
  local -a identity_hashes

  release_signing_keychain_path="${release_temp_dir}/woorisai-signing.keychain-db"
  signing_pem_path="${release_temp_dir}/distribution-import.pem"
  security_log="${release_temp_dir}/security-signing.log"
  identity_log="${release_temp_dir}/security-identities.log"
  keychain_password="$(/usr/bin/openssl rand -hex 32)"
  [[ "$keychain_password" =~ '^[0-9a-f]{64}$' ]] || \
    release_fail "a temporary keychain password could not be generated"

  release_original_default_keychain="$(release_keychain_path_from_security_output \
    "$(/usr/bin/security default-keychain -d user 2>"$security_log")")"
  release_original_keychain_search=()
  while IFS= read -r keychain_line; do
    [[ -n "$keychain_line" ]] || continue
    release_original_keychain_search+=(
      "$(release_keychain_path_from_security_output "$keychain_line")"
    )
  done < <(/usr/bin/security list-keychains -d user 2>"$security_log")
  (( ${#release_original_keychain_search[@]} > 0 )) || \
    release_fail "the current keychain search list could not be captured"

  if ! /usr/bin/security create-keychain -p "$keychain_password" \
    "$release_signing_keychain_path" >"$security_log" 2>&1; then
    release_fail "the temporary signing keychain could not be created"
  fi
  release_signing_keychain_created=true
  if ! /usr/bin/security set-keychain-settings -lut 21600 \
    "$release_signing_keychain_path" >"$security_log" 2>&1 || \
    ! /usr/bin/security unlock-keychain -p "$keychain_password" \
    "$release_signing_keychain_path" >"$security_log" 2>&1; then
    release_fail "the temporary signing keychain could not be configured"
  fi

  if ! /usr/bin/openssl pkcs12 \
    -in "$release_distribution_p12_path" \
    -passin "file:$release_distribution_p12_password_path" \
    -nodes \
    -out "$signing_pem_path" >"$security_log" 2>&1; then
    /bin/rm -f -- "$signing_pem_path"
    release_fail "the distribution certificate could not be opened"
  fi
  /bin/chmod 600 "$signing_pem_path"
  if ! /usr/bin/security import "$signing_pem_path" \
    -k "$release_signing_keychain_path" \
    -f pemseq \
    -T /usr/bin/codesign >"$security_log" 2>&1; then
    /bin/rm -f -- "$signing_pem_path"
    release_fail "the distribution identity could not be imported"
  fi
  /bin/rm -f -- "$signing_pem_path"

  if ! /usr/bin/security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$release_signing_keychain_path" >"$security_log" 2>&1; then
    release_fail "the distribution identity access policy could not be configured"
  fi
  unset keychain_password

  if ! /usr/bin/security find-identity -v -p codesigning \
    "$release_signing_keychain_path" >"$identity_log" 2>&1; then
    release_fail "the distribution signing identity could not be inspected"
  fi
  identity_hashes=("${(@f)$(/usr/bin/awk '
    /^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-Fa-f]{40}[[:space:]]/ { print $2 }
  ' "$identity_log")}")
  if (( ${#identity_hashes[@]} != 1 )); then
    release_fail "the distribution certificate must contain exactly one valid signing identity"
  fi
  identity_hash="${identity_hashes[1]:u}"
  [[ "$identity_hash" =~ '^[0-9A-F]{40}$' ]] || \
    release_fail "the distribution signing identity is malformed"
  release_signing_identity_sha1="$identity_hash"

  release_keychain_search_changed=true
  if ! /usr/bin/security list-keychains -d user -s \
    "$release_signing_keychain_path" >"$security_log" 2>&1; then
    release_fail "the temporary signing keychain could not be added to the search list"
  fi
  if ! /usr/bin/security default-keychain -d user -s \
    "$release_signing_keychain_path" >"$security_log" 2>&1; then
    release_fail "the temporary signing keychain could not be selected"
  fi
}

release_decode_provisioning_profile() {
  local profile_path="$1"
  local decoded_path="$2"
  local profile_log="${release_temp_dir}/profile-decode-$RANDOM.log"

  if ! /usr/bin/security cms -D -i "$profile_path" -o "$decoded_path" \
    >"$profile_log" 2>&1 || \
    ! /usr/bin/plutil -lint "$decoded_path" >/dev/null 2>&1; then
    release_fail "the provisioning profile could not be decoded"
  fi
}

release_validate_profile_metadata() {
  local decoded_path="$1"
  local profile_name profile_uuid profile_team_id profile_app_identifier
  local entitlement_team_id aps_environment get_task_allow platform
  local uuid_re='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'

  if ! profile_name="$(release_plist_value "$decoded_path" Name)" || \
    ! profile_uuid="$(release_plist_value "$decoded_path" UUID)" || \
    ! profile_team_id="$(release_plist_value "$decoded_path" 'TeamIdentifier:0')" || \
    ! profile_app_identifier="$(release_plist_value \
      "$decoded_path" 'Entitlements:application-identifier')" || \
    ! entitlement_team_id="$(release_plist_value \
      "$decoded_path" 'Entitlements:com.apple.developer.team-identifier')" || \
    ! aps_environment="$(release_plist_value \
      "$decoded_path" 'Entitlements:aps-environment')" || \
    ! get_task_allow="$(release_plist_value \
      "$decoded_path" 'Entitlements:get-task-allow')" || \
    ! platform="$(release_plist_value "$decoded_path" 'Platform:0')"; then
    release_fail "the provisioning profile metadata is incomplete"
  fi

  [[ "$profile_name" == "$release_provisioning_profile_name" ]] || \
    release_fail "the provisioning profile name does not match the approved App Store profile"
  [[ "$profile_uuid" =~ $uuid_re ]] || \
    release_fail "the provisioning profile UUID is malformed"
  [[ "$profile_team_id" == "$release_signing_team_id" && \
    "$entitlement_team_id" == "$release_signing_team_id" ]] || \
    release_fail "the provisioning profile does not belong to the approved signing team"
  [[ "$profile_app_identifier" == \
    "${release_signing_team_id}.${release_bundle_identifier}" ]] || \
    release_fail "the provisioning profile does not match the app bundle identifier"
  [[ "$aps_environment" == production && "$get_task_allow" == false ]] || \
    release_fail "the provisioning profile is not an App Store distribution profile"
  [[ "$platform" == iOS ]] || \
    release_fail "the provisioning profile is not an iOS profile"
  if /usr/bin/plutil -type ProvisionedDevices "$decoded_path" >/dev/null 2>&1; then
    release_fail "the App Store provisioning profile must not depend on registered devices"
  fi
  if [[ "$(/usr/bin/plutil -extract ProvisionsAllDevices raw \
    "$decoded_path" 2>/dev/null || true)" == true ]]; then
    release_fail "an enterprise provisioning profile cannot be used for App Store delivery"
  fi

  REPLY="$profile_uuid"
}

release_profile_contains_signing_identity() {
  local decoded_path="$1"
  local certificate_count certificate_index certificate_base64 certificate_der
  local certificate_sha1
  local matched=false

  if ! certificate_count="$(/usr/bin/plutil -extract DeveloperCertificates raw \
    -expect array "$decoded_path" 2>/dev/null)" || \
    [[ ! "$certificate_count" =~ '^[1-9][0-9]*$' ]]; then
    release_fail "the provisioning profile has no distribution certificates"
  fi

  certificate_index=0
  while (( certificate_index < certificate_count )); do
    certificate_base64="${release_temp_dir}/profile-certificate-${certificate_index}.base64"
    certificate_der="${release_temp_dir}/profile-certificate-${certificate_index}.der"
    if ! /usr/bin/plutil -extract "DeveloperCertificates.$certificate_index" raw \
      -expect data -o "$certificate_base64" "$decoded_path" >/dev/null 2>&1 || \
      ! /usr/bin/base64 -D <"$certificate_base64" >"$certificate_der" 2>/dev/null; then
      release_fail "a provisioning profile certificate could not be inspected"
    fi
    certificate_sha1="$(/usr/bin/shasum "$certificate_der" | \
      /usr/bin/awk '{ print toupper($1) }')"
    /bin/rm -f -- "$certificate_base64" "$certificate_der"
    if [[ "$certificate_sha1" == "$release_signing_identity_sha1" ]]; then
      matched=true
      break
    fi
    (( certificate_index += 1 ))
  done

  [[ "$matched" == true ]] || \
    release_fail "the distribution identity is not allowed by the approved provisioning profile"
}

release_prepare_provisioning_profile() {
  local decoded_path="${release_temp_dir}/approved-profile.plist"
  local profiles_dir="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
  local existing_sha256

  release_decode_provisioning_profile "$release_provisioning_profile_path" "$decoded_path"
  release_validate_profile_metadata "$decoded_path"
  release_profile_uuid="$REPLY"
  release_profile_contains_signing_identity "$decoded_path"
  release_profile_sha256="$(release_sha256_file "$release_provisioning_profile_path")"

  /bin/mkdir -p "$profiles_dir"
  release_installed_profile_path="${profiles_dir}/${release_profile_uuid}.mobileprovision"
  if [[ -e "$release_installed_profile_path" ]]; then
    if [[ ! -f "$release_installed_profile_path" || -L "$release_installed_profile_path" ]]; then
      release_fail "the provisioning profile install destination is not a regular file"
    fi
    existing_sha256="$(release_sha256_file "$release_installed_profile_path")"
    [[ "$existing_sha256" == "$release_profile_sha256" ]] || \
      release_fail "a different provisioning profile already uses the approved profile UUID"
    release_installed_profile_owned=false
  else
    release_installed_profile_owned=true
    /bin/cp "$release_provisioning_profile_path" "$release_installed_profile_path"
    /bin/chmod 600 "$release_installed_profile_path"
  fi
}

release_prepare_manual_signing() {
  release_log "Preparing isolated manual App Store distribution signing."
  release_prepare_signing_keychain
  release_prepare_provisioning_profile
}

release_verify_embedded_provisioning_profile() {
  local embedded_profile_path="$1"
  local embedded_sha256

  embedded_sha256="$(release_sha256_file "$embedded_profile_path")"
  [[ -n "$release_profile_sha256" && "$embedded_sha256" == "$release_profile_sha256" ]] || \
    release_fail "the app does not embed the exact approved provisioning profile"
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
  release_verify_embedded_provisioning_profile "${app_path}/embedded.mobileprovision"

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

release_b64url() {
  /usr/bin/openssl base64 -A | /usr/bin/tr '+/' '-_' | /usr/bin/tr -d '='
}

release_normalize_ec_scalar() {
  local scalar="$1"

  # `openssl asn1parse` prints the DER INTEGER content: a leading 00 sign byte when the high bit is
  # set (65-66 hex chars), or fewer than 64 when the scalar has leading zero bytes. JOSE needs a
  # fixed 32-byte (64 hex) big-endian value.
  while (( ${#scalar} > 64 )) && [[ "${scalar[1,2]}" == "00" ]]; do
    scalar="${scalar:2}"
  done
  while (( ${#scalar} < 64 )); do
    scalar="0${scalar}"
  done
  if (( ${#scalar} != 64 )); then
    release_fail "an App Store Connect token signature scalar is malformed"
  fi
  print -r -- "$scalar"
}

release_ascapi_bearer() {
  local key_path="${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_PATH]}"
  local key_id="${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}"
  local issuer="${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}"
  local now exp header payload signing_input sig_der r s sig
  local -a ints

  now="$(/bin/date +%s)"
  exp=$(( now + 1200 ))
  header="$(/usr/bin/printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$key_id" | release_b64url)"
  payload="$(/usr/bin/printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' \
    "$issuer" "$now" "$exp" | release_b64url)"
  signing_input="${header}.${payload}"

  sig_der="${release_temp_dir}/ascapi-jwt-$RANDOM.der"
  if ! /usr/bin/printf '%s' "$signing_input" | \
    /usr/bin/openssl dgst -sha256 -sign "$key_path" -binary >"$sig_der" 2>/dev/null; then
    /bin/rm -f -- "$sig_der"
    release_fail "the App Store Connect API token could not be signed"
  fi
  ints=("${(@f)$(/usr/bin/openssl asn1parse -inform DER -in "$sig_der" 2>/dev/null | \
    /usr/bin/awk -F: '/INTEGER/{print $NF}')}")
  /bin/rm -f -- "$sig_der"
  (( ${#ints[@]} == 2 )) || \
    release_fail "the App Store Connect API token signature is malformed"
  r="$(release_normalize_ec_scalar "${ints[1]}")"
  s="$(release_normalize_ec_scalar "${ints[2]}")"
  sig="$(/usr/bin/printf '%s%s' "$r" "$s" | /usr/bin/xxd -r -p | release_b64url)"

  print -r -- "${signing_input}.${sig}"
}

release_ascapi_get() {
  local path="$1"
  local bearer="$2"
  local out="$3"
  local http_code=""

  http_code="$(/usr/bin/curl --silent --show-error --location --max-time 60 \
    --write-out '%{http_code}' --output "$out" \
    --header "Authorization: Bearer ${bearer}" \
    "${release_ascapi_base}${path}" 2>/dev/null)" || return 1
  [[ "$http_code" == 200 ]]
}

release_ascapi_assign_build() {
  local bearer="$1"
  local group_id="$2"
  local build_id="$3"
  local http_code=""

  http_code="$(/usr/bin/curl --silent --show-error --location --max-time 60 \
    --request POST --write-out '%{http_code}' --output /dev/null \
    --header "Authorization: Bearer ${bearer}" \
    --header "Content-Type: application/json" \
    --data "$(/usr/bin/printf '{"data":[{"type":"builds","id":"%s"}]}' "$build_id")" \
    "${release_ascapi_base}/v1/betaGroups/${group_id}/relationships/builds" 2>/dev/null)" || \
    return 1
  [[ "$http_code" == 204 ]]
}

release_assign_build_to_internal_group() {
  local marketing_version="$1"
  local build_number="$2"
  local group_name="$3"
  local bearer app_id build_id group_id
  local response="${release_temp_dir}/ascapi-response-$RANDOM.json"
  local -i attempt=0

  release_log "Assigning build ${marketing_version} (${build_number}) to internal group '${group_name}'."
  bearer="$(release_ascapi_bearer)"

  if ! release_ascapi_get \
    "/v1/apps?filter%5BbundleId%5D=${release_bundle_identifier}&fields%5Bapps%5D=bundleId&limit=1" \
    "$bearer" "$response"; then
    release_fail "the App Store Connect app record could not be queried"
  fi
  app_id="$(/usr/bin/jq --raw-output '.data[0].id // empty' "$response")"
  [[ -n "$app_id" ]] || \
    release_fail "no App Store Connect app was found for ${release_bundle_identifier}"

  # The build can lag briefly behind altool's processing wait before it is queryable.
  build_id=""
  while (( attempt < 10 )); do
    if release_ascapi_get \
      "/v1/builds?filter%5Bapp%5D=${app_id}&filter%5BpreReleaseVersion.version%5D=${marketing_version}&filter%5Bversion%5D=${build_number}&fields%5Bbuilds%5D=version&limit=1" \
      "$bearer" "$response"; then
      build_id="$(/usr/bin/jq --raw-output '.data[0].id // empty' "$response")"
      [[ -n "$build_id" ]] && break
    fi
    (( attempt += 1 ))
    /bin/sleep 15
  done
  [[ -n "$build_id" ]] || \
    release_fail "uploaded build ${marketing_version} (${build_number}) did not become visible in App Store Connect"

  if ! release_ascapi_get \
    "/v1/betaGroups?filter%5Bapp%5D=${app_id}&filter%5BisInternalGroup%5D=true&fields%5BbetaGroups%5D=name&limit=200" \
    "$bearer" "$response"; then
    release_fail "App Store Connect beta groups could not be queried"
  fi
  group_id="$(/usr/bin/jq --raw-output --arg name "$group_name" \
    'first(.data[] | select(.attributes.name == $name) | .id) // empty' "$response")"
  [[ -n "$group_id" ]] || \
    release_fail "no internal TestFlight group named '${group_name}' was found (upload already succeeded)"

  if ! release_ascapi_assign_build "$bearer" "$group_id" "$build_id"; then
    release_fail "the build could not be assigned to internal group '${group_name}' (upload already succeeded)"
  fi
  /bin/rm -f -- "$response"
  release_log "Assigned build to internal TestFlight group '${group_name}'."
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
  local source_revision archive_tree_sha256 ipa_sha256
  local validation_status=not-run
  local upload_status=not-run
  local app_store_build_identifier=not-applicable
  local validation_log="${release_temp_dir}/altool-validate.log"
  local upload_log="${release_temp_dir}/altool-upload.log"

  if [[ "$should_upload" == true ]]; then
    release_verify_upload_source_clean
  fi
  source_revision="$(release_source_revision)"
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
  archive_tree_sha256="$(release_archive_tree_sha256 "$archive_path")"
  ipa_sha256="$(release_sha256_file "$ipa_path")"

  authentication_key_path="$(release_prepare_authentication_key "$private_key_dir")"
  export API_PRIVATE_KEYS_DIR="$private_key_dir"
  release_log "Validating the IPA with App Store Connect."
  if ! /usr/bin/xcrun altool --validate-app -f "$ipa_path" -t ios \
    --api-key "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" \
    --api-issuer "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" \
    --output-format json >"$validation_log" 2>&1; then
    release_fail "App Store Connect IPA validation failed; provider output was suppressed"
  fi
  validation_status=succeeded

  if [[ "$should_upload" == true ]]; then
    release_log "Uploading the validated IPA and waiting for App Store Connect processing."
    if ! /usr/bin/xcrun altool --upload-package "$ipa_path" \
      --api-key "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" \
      --api-issuer "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" \
      --wait --output-format json >"$upload_log" 2>&1; then
      release_fail "App Store Connect upload or processing failed; provider output was suppressed"
    fi
    upload_status=succeeded
    app_store_build_identifier=not-reported
    if app_store_build_identifier="$(release_extract_app_store_build_identifier "$upload_log")"; then
      :
    else
      app_store_build_identifier=not-reported
    fi
    release_log "TestFlight upload and processing completed."
  else
    upload_status=skipped
    release_log "Signed IPA validation completed; upload was skipped."
  fi

  unset API_PRIVATE_KEYS_DIR
  /bin/rm -f -- "$authentication_key_path"
  /bin/rmdir "$private_key_dir" || \
    release_fail "the temporary App Store Connect key directory could not be removed"

  release_write_evidence \
    "$source_revision" \
    "$marketing_version" \
    "$build_number" \
    "$archive_tree_sha256" \
    "$ipa_sha256" \
    "$validation_status" \
    "$upload_status" \
    "$app_store_build_identifier"

  if [[ "$should_upload" == true && -n "$release_beta_group" ]]; then
    release_assign_build_to_internal_group \
      "$marketing_version" "$build_number" "$release_beta_group"
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

  unset API_PRIVATE_KEYS_DIR 2>/dev/null || true

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
      --evidence-file)
        (( $# >= 2 )) || { release_usage; return 2; }
        release_evidence_path="$2"
        shift 2
        ;;
      --distribution-p12)
        (( $# >= 2 )) || { release_usage; return 2; }
        release_distribution_p12_path="$2"
        shift 2
        ;;
      --distribution-p12-password-file)
        (( $# >= 2 )) || { release_usage; return 2; }
        release_distribution_p12_password_path="$2"
        shift 2
        ;;
      --provisioning-profile)
        (( $# >= 2 )) || { release_usage; return 2; }
        release_provisioning_profile_path="$2"
        shift 2
        ;;
      --beta-group)
        (( $# >= 2 )) || { release_usage; return 2; }
        release_beta_group="$2"
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

  release_verify_evidence_destination

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
    release_validate_private_input_file \
      "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_PATH]}" \
      "the App Store Connect API key" \
      .p8
  fi

  if [[ "$static_only" == false ]] || release_signing_inputs_configured; then
    release_validate_signing_inputs
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

  release_prepare_manual_signing
  marketing_version="${WOORISAI_ENV_VALUES[IOS_MARKETING_VERSION]}"
  build_number="${WOORISAI_ENV_VALUES[IOS_BUILD_NUMBER]}"
  if [[ "$no_upload" == true ]]; then
    release_archive_and_export "$marketing_version" "$build_number" "$export_options_path" false
  else
    release_archive_and_export "$marketing_version" "$build_number" "$export_options_path" true
  fi
}

if [[ "${ZSH_EVAL_CONTEXT:-toplevel}" == toplevel ]]; then
  trap release_exit_handler EXIT ZERR
  trap 'exit 130' HUP INT TERM
  release_main "$@"
fi
