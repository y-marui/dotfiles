#!/usr/bin/env bash
# Verify update routing without invoking sudo, APT or a real container runtime.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export TEST_LOG="$test_dir/commands"
export PATH="$test_dir/bin:/usr/bin:/bin"
cat > "$test_dir/bin/bash" <<'SH'
#!/bin/bash
set -euo pipefail
if [[ "$1" == */scripts/update-prezto.sh ]]; then
  exit 0
fi
exec /bin/bash "$@"
SH
cat > "$test_dir/bin/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == test ]]; then
  exec /bin/test "${@:2}"
fi
printf '%s\n' "$*" >> "$TEST_LOG"
SH
cat > "$test_dir/bin/ghq-update" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ghq-update %s\n' "$*" >> "$TEST_LOG"
SH
chmod +x "$test_dir/bin/bash" "$test_dir/bin/sudo" "$test_dir/bin/ghq-update"
cat > "$test_dir/bin/systemctl" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$test_dir/bin/systemctl"
touch "$test_dir/compose.env"
HOMEBRIDGE_COMPOSE_ENV="$test_dir/compose.env" bash "$repo_dir/scripts/update-rpi-homebridge.sh" > "$test_dir/output"
grep -q 'docker compose .* config --quiet' "$TEST_LOG"
grep -q 'docker compose .* pull' "$TEST_LOG"
grep -q 'docker compose .* up -d' "$TEST_LOG"
if grep -Eq 'hb-service|npm|systemctl restart homebridge' "$TEST_LOG"; then
  echo 'FAIL: native Homebridge update attempted in container mode' >&2
  exit 1
fi
echo 'PASS: container update avoids native Homebridge and npm commands'

: > "$TEST_LOG"
HOMEBRIDGE_COMPOSE_ENV="$test_dir/missing.env" bash "$repo_dir/scripts/update-rpi-homebridge.sh" > "$test_dir/output"
grep -q 'apt update' "$TEST_LOG"
if grep -Eq 'docker|hb-service|npm|systemctl restart homebridge' "$TEST_LOG"; then
  echo 'FAIL: disabled/absent Homebridge was updated or restarted' >&2
  exit 1
fi
echo 'PASS: OS updates do not reactivate a disabled legacy Homebridge'

# A bad Compose configuration must fail before even an OS update is attempted.
cat > "$test_dir/bin/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == test ]]; then
  exec /bin/test "${@:2}"
fi
if [[ "$1" == docker ]]; then
  exit 1
fi
echo 'FAIL: update ran after invalid Compose configuration' >&2
exit 99
SH
if HOMEBRIDGE_COMPOSE_ENV="$test_dir/compose.env" bash "$repo_dir/scripts/update-rpi-homebridge.sh" > "$test_dir/output" 2>&1; then
  echo 'FAIL: invalid Compose configuration was accepted' >&2
  exit 1
fi
if grep -q 'FAIL:' "$test_dir/output"; then
  cat "$test_dir/output" >&2
  exit 1
fi
echo 'PASS: invalid Compose configuration stops all update operations'
