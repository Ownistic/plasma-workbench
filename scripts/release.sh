#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 --checklist /absolute/path/to/completed-checklist.md [--build-dir DIR]" >&2
    exit 2
}

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build-release}"
CHECKLIST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --checklist)
            [[ $# -ge 2 ]] || usage
            CHECKLIST="$2"
            shift 2
            ;;
        --build-dir)
            [[ $# -ge 2 ]] || usage
            BUILD_DIR="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

[[ -n "$CHECKLIST" && -f "$CHECKLIST" ]] || {
    echo "A completed release checklist is required." >&2
    exit 1
}
[[ "$CHECKLIST" = /* ]] || {
    echo "The checklist path must be absolute." >&2
    exit 1
}
if rg -q '^\s*- \[ \]' "$CHECKLIST" || ! rg -q '^\s*- \[x\]' "$CHECKLIST"; then
    echo "The release checklist is incomplete." >&2
    exit 1
fi

for command_name in cmake ctest git kpackagetool6 ninja rg tee; do
    command -v "$command_name" >/dev/null || {
        echo "$command_name is required." >&2
        exit 1
    }
done

[[ -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] || {
    echo "Release requires a clean checkout." >&2
    exit 1
}

VERSION="$(sed -nE 's/^project\(Workbench VERSION ([^ )]+).*/\1/p' "$PROJECT_ROOT/CMakeLists.txt")"
[[ -n "$VERSION" ]] || { echo "Could not read the Workbench version." >&2; exit 1; }
TAG="v${VERSION}"
! git -C "$PROJECT_ROOT" rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null || {
    echo "Refusing to overwrite existing tag ${TAG}." >&2
    exit 1
}

EVIDENCE_DIR="${BUILD_DIR}/release-evidence/${TAG}"
mkdir -p "$EVIDENCE_DIR"
cp "$CHECKLIST" "${EVIDENCE_DIR}/manual-checklist.md"

cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
    -DWORKBENCH_ENABLE_COVERAGE=ON \
    -DWORKBENCH_ENABLE_TEST_ADAPTERS=ON
cmake --build "$BUILD_DIR" --target fast-test |& tee "${EVIDENCE_DIR}/fast-test.log"

# Reconfigure without adapters before packaging or launching the black-box app.
cmake -S "$PROJECT_ROOT" -B "$BUILD_DIR" -G Ninja \
    -DWORKBENCH_ENABLE_COVERAGE=OFF \
    -DWORKBENCH_ENABLE_TEST_ADAPTERS=OFF
cmake --build "$BUILD_DIR" --target package-plasmoid |& tee "${EVIDENCE_DIR}/package.log"
ctest --test-dir "$BUILD_DIR" -L packaging --output-on-failure |& tee "${EVIDENCE_DIR}/packaging-tests.log"
cmake --build "$BUILD_DIR" --target benchmark-repository |& tee "${EVIDENCE_DIR}/benchmark.log"
cmake --build "$BUILD_DIR" --target e2e |& tee "${EVIDENCE_DIR}/appium.log"

git -C "$PROJECT_ROOT" tag -a "$TAG" -m "Workbench ${VERSION}"
git -C "$PROJECT_ROOT" show --no-patch --format=fuller "$TAG" > "${EVIDENCE_DIR}/tag.txt"
echo "Release qualified and tagged locally: ${TAG}"
