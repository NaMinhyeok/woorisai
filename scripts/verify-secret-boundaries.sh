#!/usr/bin/env bash

set +x
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'ERROR: secret boundary verification must run inside a Git worktree.\n' >&2
  exit 2
}
cd "$repo_root"

failure=0

report_path() {
  local reason=$1
  local path=$2

  printf 'ERROR: %s: ' "$reason" >&2
  printf '%q\n' "$path" >&2
}

is_prohibited_tracked_path() {
  local path=$1
  local lowercase_path
  local basename

  lowercase_path=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  basename=${lowercase_path##*/}

  case "/$lowercase_path/" in
    */secrets/* | */.private/*)
      return 0
      ;;
  esac

  case "$basename" in
    .env | .env.*)
      case "$basename" in
        *.example)
          ;;
        *)
          return 0
          ;;
      esac
      ;;
  esac

  case "$basename" in
    *.p8 | *.p12 | *.mobileprovision | *.pem | *.key | *.jks | *.keystore)
      return 0
      ;;
    googleservice-info*.plist)
      return 0
      ;;
    *firebase*service*account*.json | *service*account*firebase*.json | *firebase*adminsdk*.json)
      return 0
      ;;
  esac

  return 1
}

while IFS= read -r -d '' tracked_path; do
  if is_prohibited_tracked_path "$tracked_path"; then
    report_path 'prohibited high-risk tracked path' "$tracked_path"
    failure=1
  fi
done < <(git ls-files -z)

# Keep signatures structural so this verifier does not contain a matching example.
private_key_pattern='-----BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]]+|DSA[[:space:]]+|OPENSSH[[:space:]]+|ENCRYPTED[[:space:]]+)?PRIVATE[[:space:]]+KEY-----|-----BEGIN[[:space:]]+PGP[[:space:]]+PRIVATE[[:space:]]+KEY[[:space:]]+BLOCK-----'
github_token_pattern='gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}'
aws_token_pattern='(AKIA|ASIA)[0-9A-Z]{16}'
google_token_pattern='AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z._-]{20,}|GOCSPX-[0-9A-Za-z_-]{20,}'
service_account_pattern='"type"[[:space:]]*:[[:space:]]*"service_account"'
secret_signature_pattern="${private_key_pattern}|${github_token_pattern}|${aws_token_pattern}|${google_token_pattern}|${service_account_pattern}"

while IFS= read -r -d '' matched_path; do
  report_path 'secret-like content signature in tracked text' "$matched_path"
  failure=1
done < <(git grep -I -z -l -E -e "$secret_signature_pattern" -- 2>/dev/null || true)

while IFS= read -r -d '' workflow_path; do
  workflow_event_reported=0
  workflow_pin_reported=0

  if [[ -L $workflow_path ]]; then
    report_path 'workflow files must not be symbolic links' "$workflow_path"
    failure=1
    continue
  fi

  while IFS= read -r workflow_line || [[ -n "$workflow_line" ]]; do
    trimmed_line=${workflow_line#"${workflow_line%%[![:space:]]*}"}

    case "$trimmed_line" in
      '' | \#*)
        continue
        ;;
    esac

    code_line=${trimmed_line%%#*}

    if [[ $workflow_event_reported -eq 0 ]] &&
      printf '%s\n' "$code_line" | grep -Eq '(^|[^A-Za-z0-9_])pull_request_target([^A-Za-z0-9_]|$)'; then
      report_path 'pull_request_target is forbidden in workflows' "$workflow_path"
      workflow_event_reported=1
      failure=1
    fi

    if ! printf '%s\n' "$code_line" | grep -Eq '^(-[[:space:]]*)?uses[[:space:]]*:'; then
      continue
    fi

    uses_ref=${code_line#*:}
    uses_ref=${uses_ref#"${uses_ref%%[![:space:]]*}"}
    uses_ref=${uses_ref%"${uses_ref##*[![:space:]]}"}

    case "$uses_ref" in
      \"*\")
        uses_ref=${uses_ref#\"}
        uses_ref=${uses_ref%\"}
        ;;
      \'*\')
        uses_ref=${uses_ref#\'}
        uses_ref=${uses_ref%\'}
        ;;
    esac

    case "$uses_ref" in
      ./*)
        continue
        ;;
    esac

    pinned=1
    case "$uses_ref" in
      *@*)
        action_path=${uses_ref%@*}
        action_revision=${uses_ref##*@}

        if ! printf '%s\n' "$action_path" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[^@[:space:]]+)*$'; then
          pinned=0
        elif [[ ${#action_revision} -ne 40 ]] || ! printf '%s\n' "$action_revision" | grep -Eq '^[0-9A-Fa-f]+$'; then
          pinned=0
        fi
        ;;
      *)
        pinned=0
        ;;
    esac

    if [[ $pinned -eq 0 && $workflow_pin_reported -eq 0 ]]; then
      report_path 'external workflow action is not pinned to a full 40-hex commit SHA' "$workflow_path"
      workflow_pin_reported=1
      failure=1
    fi
  done < "$workflow_path"
done < <(git ls-files -z -- '.github/workflows/*.yml' '.github/workflows/*.yaml')

if [[ $failure -ne 0 ]]; then
  printf 'Secret boundary verification failed.\n' >&2
  exit 1
fi

printf 'Secret boundary verification passed.\n'
