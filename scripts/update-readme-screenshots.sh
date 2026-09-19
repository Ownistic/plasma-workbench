#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 OwnisticApps
# SPDX-License-Identifier: LGPL-3.0-or-later

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
readonly ARTIFACT_DIR="${BUILD_DIR}/appium-artifacts/compact"
readonly OUTPUT_DIR="${ROOT_DIR}/docs/screenshots"
readonly CAPTURE_GEOMETRY="502x530+29+115"

command -v magick >/dev/null 2>&1 || {
    echo "ImageMagick is required to prepare README screenshots." >&2
    exit 1
}

WORKBENCH_README_SCREENSHOTS=1 ctest --test-dir "${BUILD_DIR}" -R '^WorkbenchAppiumE2E$' --output-on-failure
mkdir -p "${OUTPUT_DIR}"

magick "${ARTIFACT_DIR}/daily-editor-compact-board.png" \
    -crop "${CAPTURE_GEOMETRY}" +repage -strip \
    "${OUTPUT_DIR}/workbench-board.png"
magick "${ARTIFACT_DIR}/daily-editor-compact-populated.png" \
    -crop "${CAPTURE_GEOMETRY}" +repage -strip \
    "${OUTPUT_DIR}/workbench-daily-report.png"
magick "${ARTIFACT_DIR}/daily-editor-compact-editing.png" \
    -crop "${CAPTURE_GEOMETRY}" +repage -strip \
    "${OUTPUT_DIR}/workbench-session-editor.png"
magick "${ARTIFACT_DIR}/daily-editor-compact-year-populated.png" \
    -crop "${CAPTURE_GEOMETRY}" +repage -strip \
    "${OUTPUT_DIR}/workbench-year-heatmap.png"

echo "Updated README screenshots in ${OUTPUT_DIR}."
