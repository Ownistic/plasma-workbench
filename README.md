# Work Todo

Work Todo is a KDE Plasma 6 desktop widget for personal task management and local work-time tracking.

## Build and Test

The data repository is QML JavaScript using `QtQuick.LocalStorage`. A small Qt 6 QML module supplies IANA timezone and daylight-saving-safe report calculations.

```sh
cmake -S . -B build -G Ninja
cmake --build build
ctest --test-dir build --output-on-failure
```

Use Qt 6 tooling explicitly on this system:

```sh
/usr/lib/qt6/bin/qmllint -I build/qml package/contents/ui
/usr/lib/qt6/bin/qmltestrunner -import build/qml -input tests/qml
```

Install both the QML plugin and plasmoid to the chosen prefix:

```sh
cmake --install build --prefix "$HOME/.local"
```

Install `plasma-sdk` before visual testing with `plasmoidviewer`.

## Documentation

- [PRD.md](PRD.md): Product requirements and acceptance criteria.
- [KDE_PLASMA_API.md](KDE_PLASMA_API.md): Plasma 6, Kirigami, KConfig, and chart APIs.
- [QT_QML_API.md](QT_QML_API.md): QML, model, drag, timer, and SQLite guidance.
- [PERSISTENCE_AND_REPORTING.md](PERSISTENCE_AND_REPORTING.md): Schema, transitions, and report rules.
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md): Environment, tests, and release workflow.
- [REFERENCES.md](REFERENCES.md): Primary upstream references.

