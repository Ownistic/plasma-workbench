# End-to-end tests

Workbench uses KDE's `selenium-webdriver-at-spi` Appium driver for black-box
tests of the packaged plasmoid. The driver starts a clean XDG home, isolated
D-Bus session, and nested KWin compositor, so tests do not access the installed
widget or its database.

## Install system dependencies

On Arch Linux or CachyOS:

```sh
sudo pacman -S --needed \
    at-spi2-core base-devel cmake extra-cmake-modules kpipewire kwayland \
    kwin kwindowsystem ninja plasma-wayland-protocols plasma-workspace \
    python-atspi python-gobject ruby uv
```

Then build the KDE driver and create the project-local Python environment:

```sh
./scripts/setup-e2e.sh
```

The script installs all test tooling below `build/e2e-tools/`, reconfigures the
project to find it, and leaves the host Python installation unchanged. The
driver is pinned to a tested revision. Its virtual environment deliberately
inherits system packages so it can use Arch's PyGObject bindings.

## Run

```sh
cmake --build build --target e2e
```

The first test creates an isolated category through the user interface, opens
the Day and Year reports, navigates back ten times, and verifies that the
`plasmawindowed` process remains alive without unbounded resident-memory growth.
Failure screenshots and driver logs are written to `build/appium-artifacts/`.

Controls used by an E2E test must have a stable `Accessible.name` or
`objectName`. Prefer selectors that describe user-visible behavior; do not
locate controls using screen coordinates.
