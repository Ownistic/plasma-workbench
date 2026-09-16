#!/usr/bin/env bash
set -euo pipefail

# Retain this package ID so upgrades preserve existing Plasma configuration.
readonly PLASMOID_ID="io.github.ownisticapps.worktodo"

command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 is required." >&2; exit 1; }

kpackagetool6 --type Plasma/Applet --remove "${PLASMOID_ID}"
echo "Removed ${PLASMOID_ID}."
