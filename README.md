# Work Todo

Work Todo is a KDE Plasma 6 desktop widget for personal task management and local work-time tracking.

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
/usr/lib/qt6/bin/qmllint -I build/qml package/contents/ui
/usr/lib/qt6/bin/qmltestrunner -import build/qml -input tests/qml
```

Build the self-contained plasmoid, then create a release archive and install it with `kpackagetool6`:

```sh
cmake --build build --target package-plasmoid
kpackagetool6 --type Plasma/Applet --install build/work-todo-0.1.0.plasmoid
```

The `package-plasmoid` target stages `package/`, uses a fixed `SOURCE_DATE_EPOCH`, and writes a ZIP-compatible `.plasmoid` whose root contains `metadata.json` and `contents/`. The native timezone module is placed in `package/contents/ui/time/` during the build and is included with the archive.

Use the convenience scripts for a user-scoped install, upgrade, or removal:

```sh
./scripts/install.sh
./scripts/update.sh
./scripts/remove.sh
```

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

