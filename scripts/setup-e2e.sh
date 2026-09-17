#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
readonly TOOL_ROOT="${BUILD_DIR}/e2e-tools"
readonly DRIVER_SOURCE="${TOOL_ROOT}/selenium-webdriver-at-spi"
readonly DRIVER_BUILD="${TOOL_ROOT}/selenium-webdriver-at-spi-build"
readonly DRIVER_PREFIX="${TOOL_ROOT}/prefix"
readonly VIRTUAL_ENV_DIR="${TOOL_ROOT}/venv"
readonly DRIVER_REVISION="${SELENIUM_WEBDRIVER_AT_SPI_REVISION:-d45a21e8f1b3591dc921f0be85f1ecd834cbe413}"
readonly DRIVER_CMAKE_DIR="${DRIVER_PREFIX}/lib/cmake/SeleniumWebDriverATSPI"

for command_name in cmake git kwin_wayland ninja plasmawindowed python3 ruby uv; do
    command -v "${command_name}" >/dev/null || {
        echo "${command_name} is required." >&2
        exit 1
    }
done

python3 -c "import gi, pyatspi" >/dev/null 2>&1 || {
    echo "python-atspi and python-gobject are required." >&2
    exit 1
}

if [[ -d "${DRIVER_SOURCE}/.git" ]]; then
    git -C "${DRIVER_SOURCE}" fetch --depth 1 origin "${DRIVER_REVISION}"
else
    git clone --no-checkout https://invent.kde.org/sdk/selenium-webdriver-at-spi.git "${DRIVER_SOURCE}"
fi
git -C "${DRIVER_SOURCE}" checkout --detach "${DRIVER_REVISION}"

cmake -S "${DRIVER_SOURCE}" -B "${DRIVER_BUILD}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${DRIVER_PREFIX}"
cmake --build "${DRIVER_BUILD}"
cmake --install "${DRIVER_BUILD}"

uv venv --allow-existing --seed --system-site-packages "${VIRTUAL_ENV_DIR}"
uv pip install --python "${VIRTUAL_ENV_DIR}/bin/python" \
    -r "${DRIVER_SOURCE}/requirements.txt" \
    -r "${PROJECT_ROOT}/tests/e2e/requirements.txt"

if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" \
        -DSeleniumWebDriverATSPI_DIR="${DRIVER_CMAKE_DIR}" \
        -DPython3_EXECUTABLE="${VIRTUAL_ENV_DIR}/bin/python"
else
    cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" -G Ninja \
        -DSeleniumWebDriverATSPI_DIR="${DRIVER_CMAKE_DIR}" \
        -DPython3_EXECUTABLE="${VIRTUAL_ENV_DIR}/bin/python"
fi

cmake --build "${BUILD_DIR}"
echo "E2E tooling is ready. Run: cmake --build ${BUILD_DIR} --target e2e"
