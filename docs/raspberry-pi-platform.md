# Raspberry Pi Platform

## Responsibilities

Raspberry Pi OS manages SSH, Tailscale, Docker, the kernel fan driver and the
user's persistent gpg-agent. Homebridge uses the official
`homebridge/homebridge` image with host networking and a persistent bind mount.
The OS and application image are updated independently; an OS rebuild must not
be the only copy of the application data.

The host foundation can be rebuilt on Raspberry Pi OS Trixie with
`bash rpi/bootstrap-platform.sh`. It installs packages, dotfiles, Tailscale,
Docker Engine/Compose plugin, Zellij and the gpg-agent configuration. Rerunning it
reconciles these components without starting Homebridge or wiping data.
Tailscale authentication and initial key loading remain interactive. Existing
conflicting container-runtime packages require review rather than automatic
removal. Mount any external persistent storage before restoring application
data; this bootstrap does not format disks or invent mount settings.

`make install-rpi` remains the legacy native-Homebridge setup. Use the dedicated
platform bootstrap for container hosts; do not run both installation paths.

## OS Updates

The normal update is `sudo apt-get update` followed by
`sudo apt-get full-upgrade`. Review changes before accepting and reboot only
after `sudo dpkg --audit` and `sudo apt-get check` succeed. Verify the running
kernel with `uname -r`, not just the installed package version. Do not use
`rpi-update` for routine stable updates.

A new boot medium and a clean OS installation remain the preferred major
upgrade route. Retain the old medium until rollback has been verified. An
explicitly approved in-place migration is an exception when no spare medium
is available. It cannot provide the same rollback guarantee: restoring APT
source files is insufficient once packages have been upgraded. Recovery may
require a card reader and reinstalling the OS.

Before an in-place upgrade, save boot/APT settings and package inventories
off-Pi, check disk space and package-manager health, verify each external
repository supports the new release, and simulate the full upgrade. Preserve
SSH/network configuration. A desktop installation also needs the Trixie
desktop replacement metapackages; do not add those to a Lite installation.
Run a long upgrade in a systemd service or persistent terminal and keep a log.
Keep an interactive privileged terminal available: an OS upgrade can change
the legacy passwordless-sudo policy while an already privileged upgrade keeps
running. Subsequent bootstrap, fan configuration and reboot may require the
user to enter their password locally. If a temporary sudoers rule is explicitly
used for maintenance, validate it with `visudo`, then remove that exact rule
after the work. Do not leave a temporary unrestricted rule as part of the host
bootstrap or assume that an old passwordless policy survives a major upgrade.

## Homebridge Migration

Back up the storage directory or download a Homebridge UI backup. Preserve
`config.json`, `persist`, `accessories`, plugin versions and UI accounts. These
files contain secrets; keep them outside Git with restricted permissions.
An archive of application settings is not a full OS image. Inspect plugin
dependencies on GPIO, Bluetooth, USB and hardware video acceleration before
moving them into a container.

1. Install Docker with `bash rpi/repos/setup_docker.sh`.
2. Pull the official stable image and record its digest with
   `sudo docker image inspect homebridge/homebridge:latest`.
3. Create a private `/etc/homebridge/compose.env` containing
   `HOMEBRIDGE_IMAGE=homebridge/homebridge@sha256:<verified-digest>` and
   `HOMEBRIDGE_DATA_DIR=/srv/homebridge`. Create the data directory explicitly.
4. Validate `rpi/homebridge/compose.yaml` with `sudo docker compose
   --env-file /etc/homebridge/compose.env -f rpi/homebridge/compose.yaml config`.
5. Stop the old Homebridge before restoring the latest backup to the new host.
   For an APT-installed source, hold its `homebridge` package and disable/mask
   its service: the package's post-install script otherwise unconditionally
   unmasks, enables and restarts the service on an APT upgrade. Keep the old
   service/data for rollback. Restore with the UI, or copy the
   storage directory and reinstall the recorded plugins as the official
   backup documentation describes.
6. Start with the same Compose options and `up -d`. Inspect logs and health,
   then verify existing accessories from the Home app. Do not reset pairings
   as a routine migration step.

The Compose healthcheck checks UI availability on port 8581. It does not prove
HomeKit accessory reachability. If the UI port changes, update the healthcheck.
Host networking provides LAN mDNS; Tailscale connectivity alone does not prove
that the new bridge is reachable from the HomeKit network.

## Image Updates and Rollback

Before updating, save a fresh application backup and the currently used image
digest. Pull the intended official stable image, record its new digest in the
private env file, and run `docker compose ... up -d`. Core/UI/Node changes inside
a container can be replaced on recreation; use image updates for these
components. Plugin state stays in the bind mount.
`scripts/update-rpi-homebridge.sh` uses the container path when the private
`/etc/homebridge/compose.env` exists (override with `HOMEBRIDGE_COMPOSE_ENV`).
It pulls the selected image reference and recreates the container, avoiding
native `hb-service` and global npm updates on container hosts. With a pinned
digest, selecting a new digest remains an explicit step before an image update.
When neither a container env file nor an enabled native Homebridge service is
present, it updates the host without updating/restarting Homebridge. This keeps
the preserved disabled migration source from advertising the same bridge again.

Check logs, health, HomeKit operation and persistence after recreation/reboot.
For rollback, stop the new container, restore a separately saved copy of the
pre-update data, set the previous image digest, and recreate. Rolling back an
image alone may not reverse application data migrations. Do not run
`docker compose down -v` or delete the persistent directory.

For migration rollback, stop the new container before unmasking/enabling and
starting the preserved old native service. Release the package hold only if
native package updates are intended. Only one copy of a bridge identity may run at a time.
Do not upgrade or discard the old host until accessory operation is confirmed.

## Remote Desktop

For browser access without a Mac client app, use Raspberry Pi Connect on a
Wayland desktop. Run `rpi-connect on` and `rpi-connect signin` as the desktop
user, then complete the displayed verification link in that user's Raspberry
Pi account. Open the Connect device list and select Screen sharing. Verify
actual desktop interaction; an active daemon alone does not prove account
linking or browser access. Keep verification codes and credentials out of Git.

For a desktop installation, use Raspberry Pi OS's WayVNC server. Enable it
with `sudo raspi-config`, Interface Options, VNC. Check that the graphical
session and `wayvnc.service` are running and port 5900 is listening. Use a
compatible client such as TigerVNC over the LAN or Tailscale, authenticating
with the Pi user's password; do not disable authentication or forward the port
on an Internet router. Do not copy credentials or generated VNC keys into Git.
The default WayVNC authentication is incompatible with macOS's built-in Screen
Sharing client. Use a compatible VNC client or browser-based Connect instead.

A successful TCP/RFB response only proves network reachability. Verify the
desktop and keyboard/mouse operation in the client, including after reboot.
For a headless desktop, inspect the existing compositor/output configuration
before forcing a display mode or changing automatic login.

## PWM Fan

On a supported Pi 4 kernel, prefer `pwm-fan` hardware PWM for a compatible
case fan. Confirm the physical GPIO and actual installed overlay first.
GPIO12 is physical pin 32. Disable analog audio when using its PWM resource;
retain original boot configuration and any legacy service for rollback.

The installed overlay's `dtoverlay -h pwm-fan` is the authority for parameters.
The standard hardware overlay uses a 40 microsecond period (25 kHz), while
`pwm-gpio-fan` uses software PWM and is not an equivalent quietness guarantee.
The setup script retains the installed overlay's default thermal levels:
75/255 at 50 C, 125 at 60 C, 175 at 67.5 C and 250 at 75 C, with 5 C
hysteresis. Verify these values against the installed help and live device
tree. Confirm physical rotation rather than inferring a stall from quietness.
Verify reliable starting and noise
on the actual fan rather than assuming every fan supports a low duty cycle.
With confirmed GPIO12 wiring and analog audio unused, apply this configuration
with `bash rpi/setup_pwm_fan.sh --gpio12`. It backs up changed boot settings and
disables `fan_pwm.service` for the next boot, leaving its current process alive
until reboot. Other existing PWM/fan overlays require manual reconciliation.

After reboot, inspect `pwm-fan` hwmon, thermal cooling-device state and GPIO pin
mux. A commanded duty cycle is not proof of physical rotation. Observe the fan
and check CPU temperature/throttling under a bounded workload. Disable the old
PWM service for the reboot that enables the overlay, avoiding two controllers
driving the same GPIO. On rollback, remove the overlay, restore the original
boot configuration and re-enable the old controller before rebooting.
Keep each fan configuration entry below the firmware's 98-character limit.
Split tuning across `dtparam` lines after `dtoverlay`; a truncated temperature
can become a valid but incorrect value. Verify live thermal trip temperatures
and `/proc/device-tree/pwm-fan/cooling-levels` after reboot, not only config text.

## Sources

- [Raspberry Pi OS](https://www.raspberrypi.com/software/operating-systems/)
- [Raspberry Pi engineer's in-place upgrade procedure](https://forums.raspberrypi.com/viewtopic.php?t=389477)
- [Docker Engine on Debian](https://docs.docker.com/engine/install/debian/)
- [Official Homebridge Docker](https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Docker)
- [Homebridge backup and restore](https://github.com/homebridge/homebridge/wiki/Backup-and-Restore)
- [Hardware PWM fan overlay](https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm/boot/dts/overlays/pwm-fan-overlay.dts)
- [SSH agent and Zellij](ssh-agent-zellij.md)
- [Raspberry Pi VNC](https://www.raspberrypi.com/documentation/computers/remote-access.html#vnc)
- [Raspberry Pi Connect](https://www.raspberrypi.com/documentation/services/connect.html)
