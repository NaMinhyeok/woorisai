#!/bin/zsh

setopt ERR_EXIT NO_UNSET PIPE_FAIL
umask 077

typeset -gr test_script_dir="${0:A:h}"

source "${test_script_dir}/release-testflight.zsh"

test_fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

test_assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || test_fail "$message"
}

test_assert_different() {
  local first="$1"
  local second="$2"
  local message="$3"

  [[ "$first" != "$second" ]] || test_fail "$message"
}

typeset -gr test_temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/woorisai-release-evidence-test.XXXXXXXX")"
typeset -g test_lifecycle_keychain_path="${test_temp_dir}/cleanup-test.keychain-db"
typeset -g test_original_default_keychain=""
typeset -ga test_original_keychain_search=()

test_cleanup() {
  if (( ${#test_original_keychain_search[@]} > 0 )); then
    /usr/bin/security list-keychains -d user -s \
      "${test_original_keychain_search[@]}" >/dev/null 2>&1 || true
  fi
  if [[ -n "$test_original_default_keychain" ]]; then
    /usr/bin/security default-keychain -d user -s \
      "$test_original_default_keychain" >/dev/null 2>&1 || true
  fi
  /usr/bin/security delete-keychain "$test_lifecycle_keychain_path" >/dev/null 2>&1 || true
  /bin/rm -rf -- "$test_temp_dir"
}

test_exit_handler() {
  local test_status=$?

  trap - EXIT ZERR HUP INT TERM
  setopt NO_ERR_EXIT
  test_cleanup
  exit "$test_status"
}

trap test_exit_handler EXIT ZERR
trap 'exit 130' HUP INT TERM

release_temp_dir="${test_temp_dir}/release-work"
/bin/mkdir -p \
  "$release_temp_dir" \
  "${test_temp_dir}/tree-a/Empty" \
  "${test_temp_dir}/tree-a/Nested" \
  "${test_temp_dir}/tree-b/Nested" \
  "${test_temp_dir}/tree-b/Empty"

export_options_path="${test_temp_dir}/ExportOptions.plist"
release_create_export_options "$export_options_path"
test_assert_equal 'manual' \
  "$(/usr/libexec/PlistBuddy -c 'Print :signingStyle' "$export_options_path")" \
  "App Store export must use manual signing"
test_assert_equal 'Apple Distribution' \
  "$(/usr/libexec/PlistBuddy -c 'Print :signingCertificate' "$export_options_path")" \
  "App Store export must require an Apple Distribution identity"
test_assert_equal '83KHWR8L3R' \
  "$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$export_options_path")" \
  "App Store export must pin the approved signing team"
test_assert_equal 'Woorisai App Store Reusable 2026' \
  "$(/usr/libexec/PlistBuddy -c \
    'Print :provisioningProfiles:com.naminhyeok.woorisai' "$export_options_path")" \
  "App Store export must pin the reusable profile"

release_distribution_p12_path="${test_temp_dir}/distribution.p12"
release_distribution_p12_password_path="${test_temp_dir}/distribution.password"
release_provisioning_profile_path="${test_temp_dir}/distribution.mobileprovision"
print -rn -- 'not-a-real-p12' >"$release_distribution_p12_path"
print -rn -- 'bounded-test-password' >"$release_distribution_p12_password_path"
print -rn -- 'not-a-real-profile' >"$release_provisioning_profile_path"
/bin/chmod 600 \
  "$release_distribution_p12_path" \
  "$release_distribution_p12_password_path" \
  "$release_provisioning_profile_path"
release_validate_signing_inputs
/bin/chmod 640 "$release_distribution_p12_path"
if (release_validate_signing_inputs >/dev/null 2>&1); then
  test_fail "group-readable signing material must be rejected"
fi
/bin/chmod 600 "$release_distribution_p12_path"
saved_profile_path="$release_provisioning_profile_path"
release_provisioning_profile_path=""
if (release_validate_signing_inputs >/dev/null 2>&1); then
  test_fail "partial signing inputs must be rejected"
fi
release_provisioning_profile_path="$saved_profile_path"

api_key_path="${test_temp_dir}/AuthKey_TEST.p8"
print -rn -- 'not-a-real-api-key' >"$api_key_path"
/bin/chmod 600 "$api_key_path"
release_validate_private_input_file "$api_key_path" "the App Store Connect API key" .p8
/bin/chmod 640 "$api_key_path"
if (release_validate_private_input_file \
  "$api_key_path" "the App Store Connect API key" .p8 >/dev/null 2>&1); then
  test_fail "a group-readable App Store Connect API key must be rejected"
fi
/bin/chmod 600 "$api_key_path"
/bin/ln -s "$api_key_path" "${test_temp_dir}/AuthKey_LINK.p8"
if (release_validate_private_input_file \
  "${test_temp_dir}/AuthKey_LINK.p8" "the App Store Connect API key" .p8 \
  >/dev/null 2>&1); then
  test_fail "a symlinked App Store Connect API key must be rejected"
fi

profile_plist_path="${test_temp_dir}/profile.plist"
/usr/bin/plutil -create xml1 "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :Name string Woorisai App Store Reusable 2026' \
  "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :UUID string 123E4567-E89B-12D3-A456-426614174000' \
  "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :TeamIdentifier array' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :TeamIdentifier:0 string 83KHWR8L3R' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :Platform array' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :Platform:0 string iOS' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :Entitlements dict' "$profile_plist_path"
/usr/libexec/PlistBuddy -c \
  'Add :Entitlements:application-identifier string 83KHWR8L3R.com.naminhyeok.woorisai' \
  "$profile_plist_path"
/usr/libexec/PlistBuddy -c \
  'Add :Entitlements:com.apple.developer.team-identifier string 83KHWR8L3R' \
  "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :Entitlements:aps-environment string production' \
  "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :Entitlements:get-task-allow bool false' \
  "$profile_plist_path"
release_validate_profile_metadata "$profile_plist_path"
test_assert_equal '123E4567-E89B-12D3-A456-426614174000' "$REPLY" \
  "the exact device-independent App Store profile must be accepted"
/usr/libexec/PlistBuddy -c 'Add :ProvisionedDevices array' "$profile_plist_path"
if (release_validate_profile_metadata "$profile_plist_path" >/dev/null 2>&1); then
  test_fail "a device-bound profile must be rejected"
fi
/usr/libexec/PlistBuddy -c 'Delete :ProvisionedDevices' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Set :Name Unapproved Profile' "$profile_plist_path"
if (release_validate_profile_metadata "$profile_plist_path" >/dev/null 2>&1); then
  test_fail "a differently named profile must be rejected"
fi
/usr/libexec/PlistBuddy -c 'Set :Name Woorisai App Store Reusable 2026' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :DeveloperCertificates array' "$profile_plist_path"
/usr/libexec/PlistBuddy -c 'Add :DeveloperCertificates:0 data YWJj' "$profile_plist_path"
release_signing_identity_sha1='D8BCE9746547BB7743E5933FBF0FC4F2D2CBCAD3'
release_profile_contains_signing_identity "$profile_plist_path"
release_signing_identity_sha1='0000000000000000000000000000000000000000'
if (release_profile_contains_signing_identity "$profile_plist_path" >/dev/null 2>&1); then
  test_fail "an identity absent from the profile must be rejected"
fi

test_original_default_keychain="$(release_keychain_path_from_security_output \
  "$(/usr/bin/security default-keychain -d user)")"
while IFS= read -r keychain_line; do
  [[ -n "$keychain_line" ]] || continue
  test_original_keychain_search+=(
    "$(release_keychain_path_from_security_output "$keychain_line")"
  )
done < <(/usr/bin/security list-keychains -d user)
(( ${#test_original_keychain_search[@]} > 0 )) || \
  test_fail "the cleanup lifecycle test requires an existing keychain search list"

lifecycle_temp_dir="${test_temp_dir}/deliberate-post-signing-failure"
lifecycle_profile_path="${lifecycle_temp_dir}/installed-profile.mobileprovision"
/bin/mkdir -p "$lifecycle_temp_dir"
print -rn -- 'temporary-profile' >"$lifecycle_profile_path"
lifecycle_status=0
/bin/zsh -c '
  setopt ERR_EXIT NO_UNSET PIPE_FAIL
  script_path="$1"
  lifecycle_temp_dir="$2"
  lifecycle_keychain_path="$3"
  lifecycle_profile_path="$4"
  original_default_keychain="$5"
  shift 5
  original_keychain_search=("$@")

  source "$script_path"
  release_temp_dir="$lifecycle_temp_dir"
  release_original_default_keychain="$original_default_keychain"
  release_original_keychain_search=("${original_keychain_search[@]}")
  release_signing_keychain_path="$lifecycle_keychain_path"
  release_installed_profile_path="$lifecycle_profile_path"
  release_installed_profile_owned=true
  trap release_exit_handler EXIT ZERR
  trap "exit 130" HUP INT TERM

  /usr/bin/security create-keychain \
    -p "focused-cleanup-keychain-password" \
    "$release_signing_keychain_path" >/dev/null 2>&1
  release_signing_keychain_created=true
  release_keychain_search_changed=true
  /usr/bin/security list-keychains -d user -s \
    "$release_signing_keychain_path" >/dev/null 2>&1
  /usr/bin/security default-keychain -d user -s \
    "$release_signing_keychain_path" >/dev/null 2>&1

  /usr/bin/false
' release-cleanup-test \
  "${test_script_dir}/release-testflight.zsh" \
  "$lifecycle_temp_dir" \
  "$test_lifecycle_keychain_path" \
  "$lifecycle_profile_path" \
  "$test_original_default_keychain" \
  "${test_original_keychain_search[@]}" \
  >/dev/null 2>&1 || lifecycle_status=$?
test_assert_equal '1' "$lifecycle_status" \
  "a raw post-signing command failure must preserve its failure status"

[[ ! -e "$lifecycle_temp_dir" ]] || \
  test_fail "EXIT cleanup must remove the release temporary directory"
[[ ! -e "$test_lifecycle_keychain_path" ]] || \
  test_fail "EXIT cleanup must delete the temporary signing keychain"
current_default_keychain="$(release_keychain_path_from_security_output \
  "$(/usr/bin/security default-keychain -d user)")"
typeset -a current_keychain_search=()
while IFS= read -r keychain_line; do
  [[ -n "$keychain_line" ]] || continue
  current_keychain_search+=(
    "$(release_keychain_path_from_security_output "$keychain_line")"
  )
done < <(/usr/bin/security list-keychains -d user)
test_assert_equal "$test_original_default_keychain" "$current_default_keychain" \
  "EXIT cleanup must restore the original default keychain"
test_assert_equal "${(j:\n:)test_original_keychain_search}" \
  "${(j:\n:)current_keychain_search}" \
  "EXIT cleanup must restore the original keychain search list"

toolchain_failure_tmp="${test_temp_dir}/toolchain-failure"
/bin/mkdir -p "$toolchain_failure_tmp"
toolchain_failure_status=0
DEVELOPER_DIR="${test_temp_dir}/missing-xcode" \
TMPDIR="$toolchain_failure_tmp" \
  "${test_script_dir}/release-testflight.zsh" \
    --env-file "${test_script_dir:h}/.env.production.example" \
    --no-upload \
    >/dev/null 2>&1 || toolchain_failure_status=$?
(( toolchain_failure_status != 0 )) || \
  test_fail "an invalid toolchain must remain a release failure"
typeset -a toolchain_failure_survivors=(
  "$toolchain_failure_tmp"/woorisai-ios-release.*(N)
)
test_assert_equal '0' "${#toolchain_failure_survivors[@]}" \
  "a raw toolchain failure must not leave a release temporary directory"
current_default_keychain="$(release_keychain_path_from_security_output \
  "$(/usr/bin/security default-keychain -d user)")"
current_keychain_search=()
while IFS= read -r keychain_line; do
  [[ -n "$keychain_line" ]] || continue
  current_keychain_search+=(
    "$(release_keychain_path_from_security_output "$keychain_line")"
  )
done < <(/usr/bin/security list-keychains -d user)
test_assert_equal "$test_original_default_keychain" "$current_default_keychain" \
  "a raw toolchain failure must preserve the default keychain"
test_assert_equal "${(j:\n:)test_original_keychain_search}" \
  "${(j:\n:)current_keychain_search}" \
  "a raw toolchain failure must preserve the keychain search list"

upload_source_repo="${test_temp_dir}/upload-source-repo"
/usr/bin/git init -q "$upload_source_repo"
/usr/bin/git -C "$upload_source_repo" config user.name 'Release Test'
/usr/bin/git -C "$upload_source_repo" config user.email 'release-test@example.invalid'
print -rn -- 'tracked-content' >"${upload_source_repo}/tracked.txt"
/usr/bin/git -C "$upload_source_repo" add tracked.txt
/usr/bin/git -C "$upload_source_repo" commit -q -m baseline
release_verify_upload_source_clean "$upload_source_repo"
print -rn -- 'changed-content' >"${upload_source_repo}/tracked.txt"
if (release_verify_upload_source_clean "$upload_source_repo" >/dev/null 2>&1); then
  test_fail "a real upload must reject tracked worktree changes"
fi
print -rn -- 'tracked-content' >"${upload_source_repo}/tracked.txt"
print -rn -- 'untracked-content' >"${upload_source_repo}/untracked.txt"
if (release_verify_upload_source_clean "$upload_source_repo" >/dev/null 2>&1); then
  test_fail "a real upload must reject untracked worktree files"
fi

print -rn -- 'alpha-content' >"${test_temp_dir}/tree-a/Nested/alpha.txt"
print -rn -- 'beta-content' >"${test_temp_dir}/tree-a/beta.bin"
/bin/ln -s 'Nested/alpha.txt' "${test_temp_dir}/tree-a/alpha-link"

print -rn -- 'beta-content' >"${test_temp_dir}/tree-b/beta.bin"
print -rn -- 'alpha-content' >"${test_temp_dir}/tree-b/Nested/alpha.txt"
/bin/ln -s 'Nested/alpha.txt' "${test_temp_dir}/tree-b/alpha-link"
/bin/chmod 700 "${test_temp_dir}/tree-a" "${test_temp_dir}/tree-b"
/bin/chmod 700 \
  "${test_temp_dir}/tree-a/Empty" \
  "${test_temp_dir}/tree-a/Nested" \
  "${test_temp_dir}/tree-b/Empty" \
  "${test_temp_dir}/tree-b/Nested"
/bin/chmod 600 \
  "${test_temp_dir}/tree-a/Nested/alpha.txt" \
  "${test_temp_dir}/tree-a/beta.bin" \
  "${test_temp_dir}/tree-b/Nested/alpha.txt" \
  "${test_temp_dir}/tree-b/beta.bin"
/usr/bin/touch -t 202001010101 "${test_temp_dir}/tree-a/Nested/alpha.txt"
/usr/bin/touch -t 202512312359 "${test_temp_dir}/tree-b/Nested/alpha.txt"

tree_a_digest="$(release_archive_tree_sha256 "${test_temp_dir}/tree-a")"
tree_a_repeat_digest="$(release_archive_tree_sha256 "${test_temp_dir}/tree-a")"
tree_b_digest="$(release_archive_tree_sha256 "${test_temp_dir}/tree-b")"
test_assert_equal "$tree_a_digest" "$tree_a_repeat_digest" \
  "the same archive tree must produce the same digest"
test_assert_equal "$tree_a_digest" "$tree_b_digest" \
  "creation order, absolute path, and timestamps must not affect the archive digest"

print -rn -- 'changed-content' >"${test_temp_dir}/tree-b/Nested/alpha.txt"
changed_content_digest="$(release_archive_tree_sha256 "${test_temp_dir}/tree-b")"
test_assert_different "$tree_a_digest" "$changed_content_digest" \
  "file content changes must change the archive digest"

print -rn -- 'alpha-content' >"${test_temp_dir}/tree-b/Nested/alpha.txt"
/bin/chmod 700 "${test_temp_dir}/tree-b/Nested/alpha.txt"
changed_mode_digest="$(release_archive_tree_sha256 "${test_temp_dir}/tree-b")"
test_assert_different "$tree_a_digest" "$changed_mode_digest" \
  "file mode changes must change the archive digest"

/bin/chmod 600 "${test_temp_dir}/tree-b/Nested/alpha.txt"
/bin/mv "${test_temp_dir}/tree-b/beta.bin" "${test_temp_dir}/tree-b/renamed.bin"
changed_path_digest="$(release_archive_tree_sha256 "${test_temp_dir}/tree-b")"
test_assert_different "$tree_a_digest" "$changed_path_digest" \
  "relative path changes must change the archive digest"

typeset -gr expected_build_identifier='123e4567-e89b-12d3-a456-426614174000'
print -r -- \
  '{"data":{"type":"builds","id":"123e4567-e89b-12d3-a456-426614174000"}}' \
  >"${test_temp_dir}/upload-build.json"
actual_build_identifier="$(release_extract_app_store_build_identifier \
  "${test_temp_dir}/upload-build.json")"
test_assert_equal "$expected_build_identifier" "$actual_build_identifier" \
  "an unambiguous App Store build response must expose only its safe identifier"

print -r -- \
  '{"data":{"type":"apps","id":"123e4567-e89b-12d3-a456-426614174000"}}' \
  >"${test_temp_dir}/upload-app.json"
if release_extract_app_store_build_identifier "${test_temp_dir}/upload-app.json" >/dev/null; then
  test_fail "a non-build provider response must not be reported as a build identifier"
fi

print -r -- 'provider output that is not JSON' >"${test_temp_dir}/upload-malformed.log"
if release_extract_app_store_build_identifier "${test_temp_dir}/upload-malformed.log" >/dev/null; then
  test_fail "malformed provider output must not be parsed or printed"
fi

release_evidence_path='relative-evidence.env'
if (release_verify_evidence_destination >/dev/null 2>&1); then
  test_fail "a relative evidence destination must fail before release work starts"
fi
release_evidence_path="${test_temp_dir}/missing-parent/release-evidence.env"
if (release_verify_evidence_destination >/dev/null 2>&1); then
  test_fail "an evidence destination with a missing parent must fail before release work starts"
fi
release_evidence_path="${test_temp_dir}/release-evidence.env"
release_verify_evidence_destination
probe_files=("${test_temp_dir}"/*.probe.*(N))
test_assert_equal '0' "${#probe_files[@]}" \
  "the evidence destination preflight must remove its probe file"
release_write_evidence \
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  '1.2.3' \
  '42' \
  "$tree_a_digest" \
  "$tree_a_repeat_digest" \
  'succeeded' \
  'succeeded' \
  "$expected_build_identifier" \
  >"${test_temp_dir}/evidence-output.log"

test_assert_equal '600' "$(/usr/bin/stat -f '%Lp' "$release_evidence_path")" \
  "the evidence file must be private"
test_assert_equal '10' "$(/usr/bin/wc -l <"$release_evidence_path" | /usr/bin/tr -d ' ')" \
  "the evidence file must contain exactly the allowlisted fields"
for expected_line in \
  'evidence_format_version=1' \
  'source_revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'bundle_identifier=com.naminhyeok.woorisai' \
  'marketing_version=1.2.3' \
  'build_number=42' \
  "archive_tree_sha256=$tree_a_digest" \
  "ipa_sha256=$tree_a_repeat_digest" \
  'validation_status=succeeded' \
  'upload_status=succeeded' \
  "app_store_build_identifier=$expected_build_identifier"; do
  /usr/bin/grep -F -x -q -- "$expected_line" "$release_evidence_path" || \
    test_fail "the evidence file is missing an expected field"
done

release_script_path="${test_script_dir}/release-testflight.zsh"
workflow_path="${test_script_dir:h:h:h}/.github/workflows/ios-testflight.yml"
project_spec_path="${test_script_dir:h}/project.yml"
if /usr/bin/grep -F -q -- 'CODE_SIGN_STYLE=Manual' "$release_script_path" || \
  /usr/bin/grep -F -q -- 'PROVISIONING_PROFILE_SPECIFIER=' "$release_script_path" || \
  /usr/bin/grep -F -q -- 'DEVELOPMENT_TEAM="$release_signing_team_id"' \
    "$release_script_path"; then
  test_fail "app-only signing settings must not be passed globally to xcodebuild"
fi
if /usr/bin/grep -F -q -- '-allowProvisioningUpdates' "$release_script_path"; then
  test_fail "release signing must not create or update provisioning assets automatically"
fi
if /usr/bin/grep -F -q -- '-T /usr/bin/security' "$release_script_path"; then
  test_fail "the imported private key must not grant the security CLI persistent access"
fi
archive_line="$(/usr/bin/grep -n -F -- '/usr/bin/xcodebuild archive \' \
  "$release_script_path" | /usr/bin/cut -d: -f1)"
authentication_key_line="$(/usr/bin/grep -n -F -- \
  'authentication_key_path="$(release_prepare_authentication_key "$private_key_dir")"' \
  "$release_script_path" | /usr/bin/cut -d: -f1)"
validation_line="$(/usr/bin/grep -n -F -- \
  'release_log "Validating the IPA with App Store Connect."' \
  "$release_script_path" | /usr/bin/cut -d: -f1)"
authentication_key_unset_line="$(/usr/bin/grep -n -F -- \
  'unset API_PRIVATE_KEYS_DIR 2>/dev/null || true' \
  "$release_script_path" | /usr/bin/tail -1 | /usr/bin/cut -d: -f1)"
if [[ ! "$archive_line" =~ '^[0-9]+$' || \
  ! "$authentication_key_line" =~ '^[0-9]+$' || \
  ! "$validation_line" =~ '^[0-9]+$' || \
  ! "$authentication_key_unset_line" =~ '^[0-9]+$' ]] || \
  (( authentication_key_line <= archive_line || authentication_key_line >= validation_line )); then
  test_fail "the App Store Connect key must be restored only after archive verification"
fi
/usr/bin/grep -F -q -- '-passin "file:$release_distribution_p12_password_path"' \
  "$release_script_path" || \
  test_fail "the PKCS#12 password must be read through a password file"
/usr/bin/grep -F -q -- '/usr/bin/security delete-keychain \' \
  "$release_script_path" || \
  test_fail "the temporary keychain must have an explicit cleanup path"
/usr/bin/grep -F -q -- \
  'Library/Developer/Xcode/UserData/Provisioning Profiles' "$release_script_path" || \
  test_fail "profiles must be installed in the current Xcode UserData location"
if /usr/bin/grep -F -q -- 'Library/MobileDevice/Provisioning Profiles' \
  "$release_script_path"; then
  test_fail "the release script must not depend on the legacy profile location"
fi
/usr/bin/ruby - "$project_spec_path" <<'RUBY'
require "yaml"

project = YAML.safe_load(File.read(ARGV.fetch(0)))
global_base = project.fetch("settings").fetch("base")
abort("the signed-device targets must retain the approved project signing team") unless
  global_base["DEVELOPMENT_TEAM"] == "83KHWR8L3R"

release = project.dig("targets", "Woorisai", "settings", "configs", "Release")
expected = {
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]" => "Apple Distribution",
  "CODE_SIGN_STYLE[sdk=iphoneos*]" => "Manual",
  "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" => "Woorisai App Store Reusable 2026"
}
abort("Woorisai Release signing settings are not exact") unless
  expected.all? { |key, value| release[key] == value }
unscoped = %w[
  CODE_SIGN_IDENTITY CODE_SIGN_STYLE PROVISIONING_PROFILE_SPECIFIER
]
abort("manual device signing must not affect Release simulator builds") if
  unscoped.any? { |key| release.key?(key) }

project.fetch("targets").each do |target_name, target|
  next if target_name == "Woorisai"
  target_release = target.dig("settings", "configs", "Release") || {}
  forbidden = %w[
    PROVISIONING_PROFILE_SPECIFIER PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]
  ]
  abort("manual app signing leaked to #{target_name}") if
    target_release["CODE_SIGN_STYLE"] == "Manual" ||
      target_release["CODE_SIGN_STYLE[sdk=iphoneos*]"] == "Manual" ||
      forbidden.any? { |key| target_release.key?(key) }
end
RUBY
for required_workflow_text in \
  'IOS_DISTRIBUTION_P12_BASE64: ${{ secrets.IOS_DISTRIBUTION_P12_BASE64 }}' \
  'IOS_DISTRIBUTION_P12_PASSWORD: ${{ secrets.IOS_DISTRIBUTION_P12_PASSWORD }}' \
  'IOS_APP_STORE_PROFILE_BASE64: ${{ secrets.IOS_APP_STORE_PROFILE_BASE64 }}' \
  '--distribution-p12-password-file "${distribution_password_path}"' \
  'trap cleanup_release_inputs EXIT'; do
  /usr/bin/grep -F -q -- "$required_workflow_text" "$workflow_path" || \
    test_fail "the TestFlight workflow is missing a protected manual-signing boundary"
done

workflow_bash_path="${test_temp_dir}/workflow-release-step.bash"
/usr/bin/awk '
  /name: Restore protected release inputs and upload the archive/ { target = 1 }
  target && /run: \|/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$workflow_path" >"$workflow_bash_path"
/bin/bash -n "$workflow_bash_path" || \
  test_fail "the TestFlight release step must parse with the system Bash 3.2"

print -- "Release evidence and signing tests passed."
