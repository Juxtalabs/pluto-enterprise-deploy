#!/usr/bin/env sh
set -eu

PLUTO_CLI_VERSION="1.0.0"
PLUTO_REPOSITORY="Juxtalabs/pluto-enterprise-deploy"
PLUTO_ROOT="${PLUTO_ROOT:-/opt/pluto}"
PLUTO_BIN="${PLUTO_BIN:-/usr/local/bin/pluto}"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

download() {
  asset="$1"
  curl --proto '=https' --tlsv1.2 -fsSL \
    "https://github.com/$PLUTO_REPOSITORY/releases/download/v$PLUTO_CLI_VERSION/$asset" \
    -o "$temporary/$asset"
}

verify_asset() {
  asset="$1"
  expected="$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset {print $1; exit}' "$temporary/SHA256SUMS")"
  actual="$(sha256sum "$temporary/$asset" | awk '{print $1}')"
  if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
    fail "Checksum verification failed for $asset"
  fi
}

[ "$(id -u)" -eq 0 ] || fail "Run this installer with sudo."
[ "$(uname -s)" = "Linux" ] || fail "Pluto Enterprise requires Linux."
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) fail "Pluto Enterprise v$PLUTO_CLI_VERSION supports x86-64 Linux only." ;;
esac

for command in curl jq openssl gzip sha256sum flock awk sed grep sort df stat install mktemp docker; do
  require_command "$command"
done
docker info >/dev/null 2>&1 || fail "Docker Engine is not running or is not accessible."
docker compose version >/dev/null 2>&1 || fail "The Docker Compose plugin is not available."

temporary="$(mktemp -d)"
trap 'rm -r "$temporary"' EXIT HUP INT TERM

download SHA256SUMS
for asset in pluto compose.yaml release.schema.json; do
  download "$asset"
  verify_asset "$asset"
done

install -d -o root -g root -m 0750 "$PLUTO_ROOT"
install -d -o root -g root -m 0750 "$PLUTO_ROOT/releases" "$PLUTO_ROOT/state" "$PLUTO_ROOT/logs"
install -d -o root -g root -m 0700 "$PLUTO_ROOT/backups"
install -o root -g root -m 0755 "$temporary/pluto" "$PLUTO_BIN"
install -o root -g root -m 0644 "$temporary/compose.yaml" "$PLUTO_ROOT/compose.yaml"
install -o root -g root -m 0644 "$temporary/release.schema.json" "$PLUTO_ROOT/release.schema.json"

printf 'Pluto deployment CLI v%s is installed.\n' "$PLUTO_CLI_VERSION"
printf 'Next: sudo pluto install app-vX.Y.Z\n'
