#!/bin/sh

set -eu

usage() {
    printf 'Usage: %s local|production [path]\n' "$0" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 2
fi

environment_name=$1
case "$environment_name" in
    local | production)
        ;;
    *)
        usage
        exit 2
        ;;
esac

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
backend_directory=$(dirname "$script_directory")
environment_file=${2:-"$backend_directory/.env.$environment_name"}

if [ ! -r "$environment_file" ] || [ -d "$environment_file" ]; then
    printf 'ERROR: environment file is not readable: %s\n' "$environment_file" >&2
    exit 1
fi

case "$environment_file" in
    *.example)
        allow_placeholders=true
        ;;
    *)
        allow_placeholders=false
        ;;
esac

awk -v environment_name="$environment_name" \
    -v allow_placeholders="$allow_placeholders" \
    -v environment_file="$environment_file" '
BEGIN {
    expected["PORT"] = 1
    expected["SPRING_DATASOURCE_URL"] = 1
    expected["SPRING_DATASOURCE_USERNAME"] = 1
    expected["SPRING_DATASOURCE_PASSWORD"] = 1
    expected["MEDIA_UPLOADS_ENABLED"] = 1
    expected["R2_ENDPOINT_URL"] = 1
    expected["R2_REGION_NAME"] = 1
    expected["R2_BUCKET_NAME"] = 1
    expected["R2_ACCESS_KEY_ID"] = 1
    expected["R2_SECRET_ACCESS_KEY"] = 1
    expected["MEDIA_UPLOAD_URL_TTL_SECONDS"] = 1
    expected["MEDIA_DOWNLOAD_URL_TTL_SECONDS"] = 1
    expected["FIREBASE_NOTIFICATIONS_ENABLED"] = 1
    expected["FIREBASE_PROJECT_ID"] = 1
    expected["FIREBASE_SERVICE_ACCOUNT_JSON_BASE64"] = 1

    example_secret["SPRING_DATASOURCE_PASSWORD"] = 1
    example_secret["R2_ENDPOINT_URL"] = 1
    example_secret["R2_BUCKET_NAME"] = 1
    example_secret["R2_ACCESS_KEY_ID"] = 1
    example_secret["R2_SECRET_ACCESS_KEY"] = 1
    example_secret["FIREBASE_PROJECT_ID"] = 1
    example_secret["FIREBASE_SERVICE_ACCOUNT_JSON_BASE64"] = 1

    production_example_secret["SPRING_DATASOURCE_URL"] = 1
    production_example_secret["SPRING_DATASOURCE_USERNAME"] = 1
}

function report(message) {
    print "ERROR: " message > "/dev/stderr"
    failures++
}

function placeholder(value) {
    return value == "" || value == "CHANGE_ME"
}

function required_value(key, reason) {
    if (allow_placeholders == "true" && placeholder(values[key])) {
        return
    }
    if (placeholder(values[key])) {
        report("key " key " is required " reason)
    }
}

function integer_in_range(key, minimum, maximum, number) {
    if (values[key] !~ /^[0-9]+$/) {
        report("key " key " must be an integer")
        return
    }
    number = values[key] + 0
    if (number < minimum || number > maximum) {
        report("key " key " must be between " minimum " and " maximum)
    }
}

{
    line = $0
    sub(/\r$/, "", line)

    content = line
    sub(/^[[:space:]]+/, "", content)
    if (content == "" || substr(content, 1, 1) == "#") {
        next
    }

    equals = index(line, "=")
    if (equals == 0) {
        report("malformed dotenv entry at line " NR)
        next
    }

    key = substr(line, 1, equals - 1)
    raw_value = substr(line, equals + 1)
    if (key !~ /^[A-Z][A-Z0-9_]*$/) {
        report("malformed dotenv key at line " NR)
        next
    }
    if (!(key in expected)) {
        report("unknown key " key " at line " NR)
        next
    }
    if (key in seen) {
        report("duplicate key " key " at line " NR)
        next
    }

    if (raw_value ~ /^[[:space:]]/ || raw_value ~ /[[:space:]]$/) {
        report("malformed value for key " key " at line " NR)
        next
    }

    value = raw_value
    first = substr(value, 1, 1)
    if (first == "\"" || first == "\047") {
        if (length(value) < 2 || substr(value, length(value), 1) != first) {
            report("unterminated quoted value for key " key " at line " NR)
            next
        }
        value = substr(value, 2, length(value) - 2)
    }

    seen[key] = 1
    values[key] = value
}

END {
    for (key in expected) {
        if (!(key in seen)) {
            report("missing key " key)
        }
    }

    if (failures > 0) {
        exit 1
    }

    if (values["MEDIA_UPLOADS_ENABLED"] != "true" &&
            values["MEDIA_UPLOADS_ENABLED"] != "false") {
        report("key MEDIA_UPLOADS_ENABLED must be true or false")
    }
    if (values["FIREBASE_NOTIFICATIONS_ENABLED"] != "true" &&
            values["FIREBASE_NOTIFICATIONS_ENABLED"] != "false") {
        report("key FIREBASE_NOTIFICATIONS_ENABLED must be true or false")
    }

    integer_in_range("PORT", 1, 65535)
    integer_in_range("MEDIA_UPLOAD_URL_TTL_SECONDS", 60, 3600)
    integer_in_range("MEDIA_DOWNLOAD_URL_TTL_SECONDS", 60, 3600)

    required_value("SPRING_DATASOURCE_URL", "for database startup")
    required_value("SPRING_DATASOURCE_USERNAME", "for database startup")
    required_value("SPRING_DATASOURCE_PASSWORD", "for database startup")

    if (!placeholder(values["SPRING_DATASOURCE_URL"]) &&
            index(values["SPRING_DATASOURCE_URL"], "jdbc:postgresql://") != 1) {
        report("key SPRING_DATASOURCE_URL must use jdbc:postgresql://")
    }

    if (values["MEDIA_UPLOADS_ENABLED"] == "true") {
        required_value("R2_ENDPOINT_URL", "when media uploads are enabled")
        required_value("R2_REGION_NAME", "when media uploads are enabled")
        required_value("R2_BUCKET_NAME", "when media uploads are enabled")
        required_value("R2_ACCESS_KEY_ID", "when media uploads are enabled")
        required_value("R2_SECRET_ACCESS_KEY", "when media uploads are enabled")
    }
    if (!placeholder(values["R2_ENDPOINT_URL"]) &&
            index(values["R2_ENDPOINT_URL"], "https://") != 1) {
        report("key R2_ENDPOINT_URL must use https://")
    }

    if (values["FIREBASE_NOTIFICATIONS_ENABLED"] == "true") {
        required_value("FIREBASE_PROJECT_ID", "when Firebase notifications are enabled")
        required_value("FIREBASE_SERVICE_ACCOUNT_JSON_BASE64",
                "when Firebase notifications are enabled")
    }

    if (allow_placeholders == "true") {
        if (values["MEDIA_UPLOADS_ENABLED"] != "false") {
            report("example key MEDIA_UPLOADS_ENABLED must default to false")
        }
        if (values["FIREBASE_NOTIFICATIONS_ENABLED"] != "false") {
            report("example key FIREBASE_NOTIFICATIONS_ENABLED must default to false")
        }
        for (key in example_secret) {
            if (!placeholder(values[key])) {
                report("example secret key " key " must contain only an empty or CHANGE_ME placeholder")
            }
        }
        if (environment_name == "production") {
            for (key in production_example_secret) {
                if (!placeholder(values[key])) {
                    report("production example key " key " must contain only an empty or CHANGE_ME placeholder")
                }
            }
        }
    }

    if (failures > 0) {
        exit 1
    }

    print "Validated " environment_name " environment contract: " environment_file
}
' "$environment_file"
