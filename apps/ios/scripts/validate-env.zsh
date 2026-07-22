#!/bin/zsh

setopt NO_UNSET

typeset -ga WOORISAI_ENV_KEYS
typeset -gA WOORISAI_ENV_VALUES

woorisai_env_error() {
  print -u2 -- "error: $1"
  return 1
}

woorisai_env_keys_for_kind() {
  local kind="$1"

  case "$kind" in
    local)
      WOORISAI_ENV_KEYS=(
        WOORISAI_FIREBASE_DEBUG_CONFIG_PATH
        WOORISAI_FIREBASE_DEBUG_REALM_SHA256
        WOORISAI_FIREBASE_RELEASE_REALM_SHA256
      )
      ;;
    production)
      WOORISAI_ENV_KEYS=(
        WOORISAI_API_HOST
        WOORISAI_FIREBASE_RELEASE_CONFIG_PATH
        WOORISAI_FIREBASE_RELEASE_REALM_SHA256
        WOORISAI_FIREBASE_DEBUG_REALM_SHA256
        APP_STORE_CONNECT_KEY_PATH
        APP_STORE_CONNECT_KEY_ID
        APP_STORE_CONNECT_ISSUER_ID
        IOS_MARKETING_VERSION
        IOS_BUILD_NUMBER
      )
      ;;
    *)
      woorisai_env_error "environment kind must be local or production"
      return 1
      ;;
  esac
}

woorisai_env_value_is_placeholder() {
  local value="$1"
  local placeholder_re='^<[^>]+>$'

  [[ -z "$value" || "$value" =~ $placeholder_re ]]
}

woorisai_validate_digest() {
  local key="$1"
  local value="$2"
  local digest_re='^[0-9A-Fa-f]{64}$'

  if [[ ! "$value" =~ $digest_re ]]; then
    woorisai_env_error "$key must be exactly 64 hexadecimal characters"
    return 1
  fi
}

woorisai_validate_absolute_file() {
  local key="$1"
  local value="$2"
  local suffix="$3"

  if [[ "$value" != /* ]]; then
    woorisai_env_error "$key must be an absolute path"
    return 1
  fi
  if [[ "$value" != *"$suffix" ]]; then
    woorisai_env_error "$key must reference a $suffix file"
    return 1
  fi
  if [[ ! -f "$value" || ! -r "$value" ]]; then
    woorisai_env_error "$key must reference a readable regular file"
    return 1
  fi
}

woorisai_validate_marketing_version() {
  local value="$1"
  local version_re='^[0-9]+\.[0-9]+\.[0-9]+$'

  if [[ ! "$value" =~ $version_re ]]; then
    woorisai_env_error "IOS_MARKETING_VERSION must use major.minor.patch"
    return 1
  fi
}

woorisai_validate_api_host() {
  local value="$1"
  local lowercase_value="${value:l}"
  local host_re='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'

  if (( ${#value} > 253 )) || [[ ! "$value" =~ $host_re ]] || \
    [[ "$lowercase_value" == *.invalid ]]; then
    woorisai_env_error \
      "WOORISAI_API_HOST must be a production DNS hostname without a scheme or path"
    return 1
  fi
}

woorisai_validate_example_values() {
  local key

  for key in "${WOORISAI_ENV_KEYS[@]}"; do
    if ! woorisai_env_value_is_placeholder "${WOORISAI_ENV_VALUES[$key]}"; then
      woorisai_env_error "example value for $key must be empty or an angle-bracket placeholder"
      return 1
    fi
  done
}

woorisai_validate_build_number() {
  local value="$1"
  local build_re='^[1-9][0-9]*$'

  if [[ ! "$value" =~ $build_re ]]; then
    woorisai_env_error "IOS_BUILD_NUMBER must be a positive integer without leading zeroes"
    return 1
  fi
}

woorisai_validate_loaded_values() {
  local kind="$1"
  local key value
  local key_id_re='^[A-Z0-9]{10}$'
  local issuer_re='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'

  for key in "${WOORISAI_ENV_KEYS[@]}"; do
    value="${WOORISAI_ENV_VALUES[$key]}"
    if woorisai_env_value_is_placeholder "$value"; then
      woorisai_env_error "$key must be configured"
      return 1
    fi
  done

  case "$kind" in
    local)
      woorisai_validate_absolute_file \
        WOORISAI_FIREBASE_DEBUG_CONFIG_PATH \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_DEBUG_CONFIG_PATH]}" \
        .plist || return 1
      woorisai_validate_digest \
        WOORISAI_FIREBASE_DEBUG_REALM_SHA256 \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_DEBUG_REALM_SHA256]}" || return 1
      woorisai_validate_digest \
        WOORISAI_FIREBASE_RELEASE_REALM_SHA256 \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_REALM_SHA256]}" || return 1
      if [[ "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_DEBUG_REALM_SHA256]:l}" == \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_REALM_SHA256]:l}" ]]; then
        woorisai_env_error "debug and release Firebase realm digests must differ"
        return 1
      fi
      ;;
    production)
      woorisai_validate_api_host \
        "${WOORISAI_ENV_VALUES[WOORISAI_API_HOST]}" || return 1
      woorisai_validate_absolute_file \
        WOORISAI_FIREBASE_RELEASE_CONFIG_PATH \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_CONFIG_PATH]}" \
        .plist || return 1
      woorisai_validate_digest \
        WOORISAI_FIREBASE_RELEASE_REALM_SHA256 \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_REALM_SHA256]}" || return 1
      woorisai_validate_digest \
        WOORISAI_FIREBASE_DEBUG_REALM_SHA256 \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_DEBUG_REALM_SHA256]}" || return 1
      if [[ "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_RELEASE_REALM_SHA256]:l}" == \
        "${WOORISAI_ENV_VALUES[WOORISAI_FIREBASE_DEBUG_REALM_SHA256]:l}" ]]; then
        woorisai_env_error "release and debug Firebase realm digests must differ"
        return 1
      fi
      woorisai_validate_absolute_file \
        APP_STORE_CONNECT_KEY_PATH \
        "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_PATH]}" \
        .p8 || return 1
      if [[ ! "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_KEY_ID]}" =~ $key_id_re ]]; then
        woorisai_env_error "APP_STORE_CONNECT_KEY_ID must be 10 uppercase letters or digits"
        return 1
      fi
      if [[ ! "${WOORISAI_ENV_VALUES[APP_STORE_CONNECT_ISSUER_ID]}" =~ $issuer_re ]]; then
        woorisai_env_error "APP_STORE_CONNECT_ISSUER_ID must be a UUID"
        return 1
      fi
      woorisai_validate_marketing_version \
        "${WOORISAI_ENV_VALUES[IOS_MARKETING_VERSION]}" || return 1
      woorisai_validate_build_number \
        "${WOORISAI_ENV_VALUES[IOS_BUILD_NUMBER]}" || return 1
      ;;
  esac
}

woorisai_parse_env() {
  local kind="$1"
  local env_file="$2"
  local mode="${3:-full}"
  local assignment_re='^([A-Z][A-Z0-9_]*)=(.*)$'
  local line key value required_key
  local -i line_number=0
  local -A allowed seen

  if [[ "$mode" != full && "$mode" != schema && "$mode" != example ]]; then
    woorisai_env_error "validation mode must be full, schema, or example"
    return 1
  fi
  if [[ ! -f "$env_file" || ! -r "$env_file" ]]; then
    woorisai_env_error "environment file must be a readable regular file"
    return 1
  fi

  woorisai_env_keys_for_kind "$kind" || return 1
  WOORISAI_ENV_VALUES=()
  for required_key in "${WOORISAI_ENV_KEYS[@]}"; do
    allowed[$required_key]=1
  done

  while IFS= read -r line || [[ -n "$line" ]]; do
    (( line_number += 1 ))
    if [[ "$line" == *$'\r'* || "$line" == *$'\t'* ]]; then
      woorisai_env_error "environment line $line_number contains a disallowed control character"
      return 1
    fi
    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi
    if [[ ! "$line" =~ $assignment_re ]]; then
      woorisai_env_error "environment line $line_number is not a KEY=value assignment"
      return 1
    fi

    key="${match[1]}"
    value="${match[2]}"
    if (( ! ${+allowed[$key]} )); then
      woorisai_env_error "environment line $line_number uses an unknown key"
      return 1
    fi
    if (( ${+seen[$key]} )); then
      woorisai_env_error "environment line $line_number duplicates $key"
      return 1
    fi
    if [[ "$value" == [[:space:]]* || "$value" == *[[:space:]] ]]; then
      woorisai_env_error "environment line $line_number has leading or trailing whitespace"
      return 1
    fi

    seen[$key]=1
    WOORISAI_ENV_VALUES[$key]="$value"
  done < "$env_file"

  for required_key in "${WOORISAI_ENV_KEYS[@]}"; do
    if (( ! ${+seen[$required_key]} )); then
      woorisai_env_error "environment file is missing $required_key"
      return 1
    fi
  done

  if [[ "$mode" == full ]]; then
    woorisai_validate_loaded_values "$kind" || return 1
  elif [[ "$mode" == example ]]; then
    woorisai_validate_example_values || return 1
  fi
}

woorisai_validate_env_usage() {
  print -u2 -- \
    "usage: validate-env.zsh --kind local|production [--schema-only|--example-only] ENV_FILE"
}

woorisai_validate_env_main() {
  local kind=""
  local mode=full
  local env_file=""

  while (( $# > 0 )); do
    case "$1" in
      --kind)
        if (( $# < 2 )); then
          woorisai_validate_env_usage
          return 2
        fi
        kind="$2"
        shift 2
        ;;
      --schema-only)
        mode=schema
        shift
        ;;
      --example-only)
        mode=example
        shift
        ;;
      --help|-h)
        woorisai_validate_env_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        woorisai_env_error "unknown option"
        woorisai_validate_env_usage
        return 2
        ;;
      *)
        if [[ -n "$env_file" ]]; then
          woorisai_env_error "only one environment file may be provided"
          return 2
        fi
        env_file="$1"
        shift
        ;;
    esac
  done

  if (( $# > 0 )); then
    if [[ -n "$env_file" || $# != 1 ]]; then
      woorisai_validate_env_usage
      return 2
    fi
    env_file="$1"
  fi
  if [[ -z "$kind" || -z "$env_file" ]]; then
    woorisai_validate_env_usage
    return 2
  fi

  woorisai_parse_env "$kind" "$env_file" "$mode" || return 1
  if [[ "$mode" == schema ]]; then
    print -- "Environment schema validated."
  elif [[ "$mode" == example ]]; then
    print -- "Environment example contract validated."
  else
    print -- "Environment configuration validated."
  fi
}

if [[ "${ZSH_EVAL_CONTEXT:-toplevel}" == toplevel ]]; then
  woorisai_validate_env_main "$@"
fi
