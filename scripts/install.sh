#!/usr/bin/env bash
set -euo pipefail

readonly PLASMOID_ID="io.github.ownisticapps.worktodo"
readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
readonly ARCHIVE="${BUILD_DIR}/work-todo-0.1.0.plasmoid"

command -v cmake >/dev/null || { echo "cmake is required." >&2; exit 1; }
command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 is required." >&2; exit 1; }

if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}"
else
    cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" -G Ninja
fi

cmake --build "${BUILD_DIR}" --target package-plasmoid
[[ -f "${ARCHIVE}" ]] || { echo "Release archive was not created: ${ARCHIVE}" >&2; exit 1; }

kpackagetool6 --type Plasma/Applet --install "${ARCHIVE}"
echo "Installed ${PLASMOID_ID}. Add Work Todo from Plasma's Add Widgets dialog."
