#!/usr/bin/env bash
# Configure a confirmed GPIO12 case fan; changes take effect on reboot.
set -euo pipefail
if [[ "${1:-}" != --gpio12 ]] || [[ $# != 1 ]]; then
  echo "Usage: bash rpi/setup_pwm_fan.sh --gpio12" >&2
  echo "Confirm GPIO12 wiring and that analog audio is unused first." >&2
  exit 1
fi
if [[ "$(uname -s)" != Linux ]] || ! grep -q 'Raspberry Pi 4' /proc/device-tree/model; then
  echo "ERROR: Raspberry Pi 4 only" >&2
  exit 1
fi
test -f /boot/firmware/overlays/pwm-fan.dtbo
config=/boot/firmware/config.txt
staged=$(mktemp)
trap 'rm -f "$staged"' EXIT
python3 - "$config" "$staged" <<'PY'
import pathlib
import re
import sys

source, target = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
begin = '# BEGIN dotfiles pwm-fan\n'
end = '# END dotfiles pwm-fan\n'
if text.count(begin) != text.count(end) or text.count(begin) > 1:
    raise SystemExit('ERROR: malformed managed fan block')
text = re.sub(re.escape(begin) + r'.*?' + re.escape(end), '', text, flags=re.S)
if re.search(r'^\s*dtoverlay=.*(?:fan|pwm)', text, re.M):
    raise SystemExit('ERROR: existing fan/PWM overlay needs manual review')
text = re.sub(r'^dtparam=audio=on$', 'dtparam=audio=off', text, flags=re.M)
text = text.rstrip() + '\n\n' + begin + '[all]\n'
text += 'dtparam=audio=off\n'
fan_lines = [
    'dtoverlay=pwm-fan,fan_gpio_12',
]
# Firmware truncates config entries after 98 characters. Keep a margin.
assert all(len(line) <= 80 for line in fan_lines)
text += '\n'.join(fan_lines) + '\n'
target.write_text(text + end)
PY
if cmp -s "$config" "$staged"; then
  echo "SKIP: PWM fan configuration already matches"
else
  backup="/var/backups/dotfiles-fan/$(date +%Y%m%d%H%M%S)"
  sudo install -d -m 0700 "$backup"
  sudo cp -a "$config" "$backup/config.txt"
  sudo install -m 0644 "$staged" "$config"
  echo "Saved previous boot configuration in $backup"
fi
if systemctl is-enabled --quiet fan_pwm.service 2>/dev/null; then
  sudo systemctl disable fan_pwm.service
  echo "Legacy fan_pwm disabled for next boot; it keeps running until reboot."
fi
echo "Reboot, then verify pwm-fan hwmon, GPIO12 mux and physical rotation."
