#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible entry point. The shared installer owns the pinned version.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../scripts/setup-zellij.sh"
