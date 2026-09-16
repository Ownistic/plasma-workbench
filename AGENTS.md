# Repository Instructions

## Build And Verification

- The native module requires CMake 3.21+, ECM 6+, Qt 6.7 (`Core`, `Qml`, and `Test`), and a C++ build toolchain. Configure and run the normal gate from the repository root:
  ```sh
  cmake -S . -B build -G Ninja
  cmake --build build
  ctest --test-dir build --output-on-failure
  ```
- Build before QML tests, linting, or `plasmoidviewer`. The build creates the native QML module under `build/qml` and copies its runtime files into the ignored `package/contents/ui/time/` directory.
- Qt tools are not necessarily on `PATH` on the supported system. Lint all top-level UI files with `/usr/lib/qt6/bin/qmllint -I build/qml package/contents/ui/*.qml`.
- `DatabaseRepository` points at the complete `tests/qml` directory, not only `tst_database.qml`. Run one QML test directly with:
  ```sh
  QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import build/qml -input tests/qml/tst_database.qml DatabaseRepository::test_repeatedInitializationKeepsSchema
  ```
  Replace the file, test-case name, and function as needed.
- Run one native time test with `./build/tests/time/tst_timemath splitsCrossMidnight`. Use `ctest --test-dir build -R '^TimeMath$' --output-on-failure` for the complete native suite.
- The 5,000-task / 100,000-session repository benchmark is intentionally outside the normal test gate. Run it with `cmake --build build --target benchmark-repository`.
- A reported UI regression is not complete without automated coverage under `tests/qml`. `VerifyUserReportedUiContracts.cmake` preserves load-time, dialog, navigation, drag, and timer contracts that ordinary Qt Quick tests have previously missed.

## Runtime Architecture

- `package/` is the installed plasmoid. `package/contents/ui/main.qml` is the entry point, and `TodoBoard.qml` coordinates models, navigation, timers, drag state, and repository reloads.
- Keep application data access behind `package/contents/code/Database.js`, which uses synchronous `QtQuick.LocalStorage`. KConfig in `package/contents/config/main.xml` is for widget preferences, not task or session data.
- Add schema changes as ordered migrations in `package/contents/code/Migrations.js`, and add upgrade coverage to `tests/qml/tst_migrations.qml`. Keep multi-row state changes transactional, and preserve trigger-enforced references and transactional session-overlap checks.
- `package/contents/code/Reports.js` aggregates repository rows, but local calendar boundaries, timezone validation, daylight-saving transitions, and interval splitting belong in the compiled `src/time` QML module. Cover those changes in `tests/time/tst_timemath.cpp`.
- Never edit or commit `package/contents/ui/time/`; CMake regenerates that bundled plugin from `src/time`.

## Compatibility And Packaging

- Do not rename the Plasma plugin ID or LocalStorage database ID `io.github.ownisticapps.worktodo`. The legacy ID preserves installed widgets, settings, and user data. Use `Workbench` for the product name and `plasma-workbench` for repository and archive names.
- Build the self-contained release with `cmake --build build --target package-plasmoid`. The archive must retain `metadata.json`, `contents/`, license files, and corresponding source; do not package only the visible QML files.
- `plasmoid-archive-install` is registered only when `kpackagetool6` exists at CMake configure time. Reconfigure after installing that tool, then run `ctest --test-dir build -R '^plasmoid-archive-install$' --output-on-failure`.
- `scripts/install.sh` and `scripts/update.sh` rebuild the archive before calling `kpackagetool6`; set `BUILD_DIR` to override their default `build/` directory.
- For visual checks after building, use `plasmoidviewer -a package -l floating -f planar`; use `-s 560x760` for the target desktop size and `QT_SCALE_FACTOR=2 ... -s 1120x1520` for 200% scaling.
