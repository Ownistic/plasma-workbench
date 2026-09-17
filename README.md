# Workbench

A card-based task manager and work-time tracker for KDE Plasma.

Workbench keeps tasks, status, categories, tracked time, and work reports directly on the Plasma desktop.

## Build and Test

The data repository is QML JavaScript using `QtQuick.LocalStorage`. A small Qt 6 QML module supplies IANA timezone and daylight-saving-safe report calculations.

```sh
cmake -S . -B build -G Ninja
cmake --build build
ctest --test-dir build --output-on-failure
```

Run the opt-in 5,000-task / 100,000-session benchmark separately:

```sh
cmake --build build --target benchmark-repository
```

Use Qt 6 tooling explicitly on this system:

```sh
/usr/lib/qt6/bin/qmllint -I build/qml package/contents/ui/*.qml
/usr/lib/qt6/bin/qmltestrunner -import build/qml -input tests/qml
```

Run black-box plasmoid tests with KDE's Appium AT-SPI driver:

```sh
./scripts/setup-e2e.sh
cmake --build build --target e2e
```

The E2E environment uses an isolated XDG home, D-Bus session, and nested KWin
compositor. See [`tests/e2e/README.md`](tests/e2e/README.md) for dependencies,
artifacts, and test-authoring conventions.

Build the self-contained plasmoid, then create a release archive and install it with `kpackagetool6`:

```sh
cmake --build build --target package-plasmoid
kpackagetool6 --type Plasma/Applet --install build/plasma-workbench-0.1.0.plasmoid
```

The `package-plasmoid` target stages `package/`, uses a fixed `SOURCE_DATE_EPOCH`, and writes a ZIP-compatible `.plasmoid` whose root contains `metadata.json` and `contents/`. The native timezone module is placed in `package/contents/ui/time/` during the build and is included with the archive.

Use the convenience scripts for a user-scoped install, upgrade, or removal:

```sh
./scripts/install.sh
./scripts/update.sh
./scripts/remove.sh
```

## Compatibility

The Plasma package and LocalStorage database identifier remains
`io.github.ownisticapps.worktodo` so upgrades retain existing widgets, settings,
tasks, tracked time, categories, and reports. This legacy technical identifier is
not the repository slug; release archives and repository references use
`plasma-workbench`.

## License

Copyright (C) 2026 OwnisticApps. Workbench is licensed under the
[GNU Lesser General Public License, version 3 or later](LICENSE).
The release archive includes the canonical LGPL text, its incorporated GPL
terms, notices, and the exact corresponding source used to build its native
module. See
[SOURCE_OFFER.md](SOURCE_OFFER.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

With `kpackagetool6` available at configure time, run the isolated archive-install smoke test after building the release target:

```sh
ctest --test-dir build -R plasmoid-archive-install --output-on-failure
```

Install `plasma-sdk` before visual testing with `plasmoidviewer`.

## Documentation

- [PRD.md](PRD.md): Product requirements and acceptance criteria.
- [KDE_PLASMA_API.md](KDE_PLASMA_API.md): Plasma 6, Kirigami, KConfig, and chart APIs.
- [QT_QML_API.md](QT_QML_API.md): QML, model, drag, timer, and SQLite guidance.
- [PERSISTENCE_AND_REPORTING.md](PERSISTENCE_AND_REPORTING.md): Schema, transitions, and report rules.
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md): Environment, tests, and release workflow.
- [REFERENCES.md](REFERENCES.md): Primary upstream references.

