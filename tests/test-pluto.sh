#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -r "$temporary"' EXIT HUP INT TERM
cd "$repository_root"

export PLUTO_ROOT="$temporary/pluto"
mkdir -p "$PLUTO_ROOT/state" "$PLUTO_ROOT/releases"
source ./pluto

[[ "$(pluto_output="$(main version)"; printf '%s' "$pluto_output")" == "pluto 1.0.0" ]]
version_is_older 1.0.0 1.0.1
if version_is_older 1.0.1 1.0.0; then
  exit 1
fi
if version_is_older 1.0.0 1.0.0; then
  exit 1
fi

printf 'current-value\n' >"$PLUTO_ROOT/state/example"
[[ "$(state_value example)" == "current-value" ]]
[[ -z "$(state_value missing)" ]]

cat >"$PLUTO_ROOT/.env" <<'EOF'
FIRST=one
SECOND=two
EOF
replace_env_value "$PLUTO_ROOT/.env" SECOND replacement
[[ "$(env_value FIRST "$PLUTO_ROOT/.env")" == "one" ]]
[[ "$(env_value SECOND "$PLUTO_ROOT/.env")" == "replacement" ]]

read_central_key <<'EOF'
valid_test_key_1234567890
EOF
[[ "$CENTRAL_KEY_VALUE" == "valid_test_key_1234567890" ]]

cat >"$temporary/valid-manifest.json" <<'EOF'
{
  "schema_version": 1,
  "release": "app-v0.9.25",
  "source_commit": "0000000000000000000000000000000000000000",
  "api_image": "ghcr.io/juxtalabs/pluto-enterprise-api@sha256:0000000000000000000000000000000000000000000000000000000000000000",
  "web_image": "ghcr.io/juxtalabs/pluto-enterprise-web@sha256:1111111111111111111111111111111111111111111111111111111111111111",
  "alembic_head": "0037",
  "minimum_pluto_cli": "1.0.0",
  "created_at": "2026-09-17T00:00:00Z"
}
EOF
validate_manifest_file app-v0.9.25 "$temporary/valid-manifest.json"

sed 's#pluto-enterprise-api#different-api#' "$temporary/valid-manifest.json" >"$temporary/invalid-manifest.json"
if PLUTO_ROOT="$temporary/reject" bash -c "source '$repository_root/pluto'; validate_manifest_file app-v0.9.25 '$temporary/invalid-manifest.json'"; then
  printf 'Manifest with an unapproved image was accepted.\n' >&2
  exit 1
fi

if printf '%s\n' \
  "invalid_key_\$(touch /tmp/not-allowed)" | PLUTO_ROOT="$temporary/reject" bash -c "source '$repository_root/pluto'; read_central_key"; then
  printf 'Malicious central key was accepted.\n' >&2
  exit 1
fi

cat >"$temporary/central-response.json" <<'EOF'
{
  "grants": [
    {
      "company_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      "installation_id": "22222222-2222-4222-8222-222222222222",
      "jws": "signed-grant-b"
    },
    {
      "company_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "installation_id": "11111111-1111-4111-8111-111111111111",
      "jws": "signed-grant-a"
    }
  ]
}
EOF
expected_companies="$(printf '%s\n' \
  aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa \
  bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb)"
[[ "$(central_company_ids_from_response <"$temporary/central-response.json")" == "$expected_companies" ]]

cat >"$temporary/central.env" <<'EOF'
SEJATI_ADMIN_URL=https://sejati-admin.juxtalabs.io
SEJATI_ADMIN_SYNC_KEY=probe_test_key_1234567890
EOF
(
  curl() {
    local config
    [[ "$*" != *probe_test_key_1234567890* ]]
    config="$(cat)"
    [[ "$config" == 'header = "Authorization: Bearer probe_test_key_1234567890"' ]]
    cat "$temporary/central-response.json"
  }
  [[ "$(probe_central "$temporary/central.env")" == "$expected_companies" ]]
)

ss() {
  printf '%s\n' 'LISTEN 0 511 127.0.0.1:18080' 'LISTEN 0 511 127.0.0.1:18888'
}
pick_web_bind_port <<'EOF'
not-a-port
80
18888
18444
EOF
[[ "$WEB_BIND_PORT" == "18444" ]]
unset -f ss

printf '{"grants":[]}\n' >"$temporary/empty-central-response.json"
if central_company_ids_from_response <"$temporary/empty-central-response.json"; then
  printf 'An empty central grant response was accepted.\n' >&2
  exit 1
fi

(
  active_grant_company_ids() {
    printf '%s\n' "$expected_companies"
  }
  grant_set_matches ignored "$expected_companies"
)

if (
  active_grant_company_ids() {
    printf '%s\n' aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
  }
  grant_set_matches ignored "$expected_companies"
); then
  printf 'A partial local grant set matched central.\n' >&2
  exit 1
fi

printf 'CLI tests passed.\n'
