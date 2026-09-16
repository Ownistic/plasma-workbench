# Development guide

This guide covers a pure-QML Plasma 6 implementation on CachyOS. Commands use POSIX shell syntax. The same commands can be entered interactively in fish unless a command depends on shell-specific assignment syntax.

## 1. Verify the environment

Run:

```bash
plasmashell --version
qtpaths6 --qt-version
```

Record the versions in the project README. Set the project’s minimum versions from APIs actually used, not from the newest installed package.

## 2. Install development dependencies

Install the tools required for a pure-QML widget:

```bash
sudo pacman -S --needed plasma-sdk kquickcharts
```

Install native build tools only if the project adds a C++ backend:

```bash
sudo pacman -S --needed base-devel cmake ninja extra-cmake-modules plasma-sdk
```

`plasma-sdk` supplies development and inspection applications. `kquickcharts` supplies the report-chart QML module.

References:

- [Arch `plasma-sdk` package](https://archlinux.org/packages/extra/x86_64/plasma-sdk/)
- [Arch `libplasma` package](https://archlinux.org/packages/extra/x86_64/libplasma/)
- [Arch `kquickcharts` package](https://archlinux.org/packages/extra/x86_64/kquickcharts/)

## 3. Create the package structure

Use this initial structure:

```text
plasma-workbench/
├── package/
│   ├── metadata.json
│   └── contents/
│       ├── code/
│       │   ├── Database.js
│       │   ├── Migrations.js
│       │   └── Reports.js
│       ├── config/
│       │   ├── config.qml
│       │   └── main.xml
│       └── ui/
│           ├── main.qml
│           ├── TodoBoard.qml
│           ├── TaskCard.qml
│           ├── CategoryHeader.qml
│           ├── TaskDetails.qml
│           ├── TimeEntryEditor.qml
│           ├── ReportsView.qml
│           └── ConfigGeneral.qml
├── tests/
└── README.md
```

Everything under `package/` becomes the installed Plasma package. Keep developer documentation, tests, screenshots, and build helpers outside that directory.

Reference: [KDE Plasma widget setup](https://develop.kde.org/docs/plasma/widget/setup/)

## 4. Select identifiers

Choose a unique reverse-domain plugin identifier before the first installed development build. Workbench retains its existing identifier for upgrade compatibility:

```text
io.github.ownisticapps.worktodo
```

Use the same identifier for:

- `KPlugin.Id` in `metadata.json`.
- The installed package directory.
- The LocalStorage database name or a product-specific derivative.
- The translation domain when translations are added.

Do not reuse the identifier of an older test widget. A user-installed package can override a system-installed package with the same identifier. The retained Workbench identifier is a legacy technical identifier, not the repository slug; use `plasma-workbench` for repository and release-archive names.

## 5. Run without installation

From the project root, run:

```bash
plasmoidviewer -a package -l floating -f planar
```

`floating` and `planar` simulate a desktop widget. In `plasmoidviewer`, the `desktop` location represents the wallpaper containment rather than a widget placed on the desktop.

Test a specific size:

```bash
plasmoidviewer -a package -l floating -f planar -s 560x760
```

Test 200 percent scaling:

```bash
QT_SCALE_FACTOR=2 plasmoidviewer -a package -l floating -f planar -s 1120x1520
```

Reference: [KDE Plasma widget testing](https://develop.kde.org/docs/plasma/widget/testing/)

## 6. Install and update the widget

Install the package for the current user:

```bash
kpackagetool6 --type=Plasma/Applet --install package
```

Update the installed package:

```bash
kpackagetool6 --type=Plasma/Applet --upgrade package
```

Remove the installed package:

```bash
kpackagetool6 --type=Plasma/Applet --remove io.github.ownisticapps.worktodo
```

After installation, open Plasma’s **Add Widgets** interface and add **Workbench** to the desktop.

## 7. Debug the widget

Enable QML debug logging for `plasmoidviewer`:

```bash
QT_LOGGING_RULES="qml.debug=true" plasmoidviewer -a package -l floating -f planar
```

For the final installed-shell test:

```bash
QT_LOGGING_RULES="qml.debug=true" plasmashell --replace
```

Use the second command carefully because it replaces the active Plasma shell process. Prefer `plasmoidviewer` during normal development.

Common failures:

| Symptom | Check |
| --- | --- |
| Widget does not appear | Confirm `X-Plasma-API-Minimum-Version`, `KPackageStructure`, and `KPlugin.Id`. |
| Blank widget | Check QML import errors and verify that the root type is `PlasmoidItem`. |
| QML module missing | Confirm the matching Arch package is installed. |
| Changes do not appear | Upgrade the installed package or run directly from the `package` directory. |
| Database query fails | Log the SQL error without logging task content. |
| Drag looks correct but resets | Persist the source-model order instead of moving only `DelegateModel.items`. |
| Timer resets while scrolling | Move timer state out of the card delegate. |

Reference: [KDE testing and QML logging](https://develop.kde.org/docs/plasma/widget/testing/)

## 8. Test strategy

### 8.1 Repository tests

Test these operations with an isolated database:

- First initialization.
- Repeated initialization.
- Every schema migration.
- Task and category create, edit, archive, and delete operations.
- Reordering with and without gaps.
- Rebalancing.
- Cross-category moves.
- Status-event corrections.
- Start, switch, pause, resume, and stop transitions.
- Repeated stop requests.
- Active-session recovery.
- Manual-session overlap rejection.

### 8.2 Report tests

Use fixed timestamps and expected second totals. Cover:

- A session within one day.
- A session crossing local midnight.
- A session crossing a week boundary.
- A session crossing a month boundary.
- A session crossing a daylight-saving transition.
- An active session in the current reporting period.
- Archived tasks with historical sessions.
- A manually corrected session.
- An empty week and empty month.

### 8.3 Interface tests

Test:

- Minimum supported size.
- Large desktop size.
- 100 and 200 percent scaling.
- Plasma light and dark themes.
- Long titles and descriptions.
- Keyboard-only navigation.
- Screen-reader accessible names.
- Drag ordering with status filters active.
- Panel compact representation.
- Plasma restart with an active session.

### 8.4 Static checks

Run Qt’s QML linter against every QML source. Use the executable path supplied by the installed Qt package if `qmllint` is not directly available on `PATH`.

Reference: [Qt QML tooling and `qmllint`](https://doc.qt.io/qt-6/qtqml-tooling-qmllint.html)

## 9. Package a release

Create a ZIP-compatible archive whose root contains `metadata.json` and `contents/`. Use the `.plasmoid` extension for the release artifact. The CMake target packages the already-built self-contained `package/` and avoids an external ZIP dependency:

```bash
cmake --build build --target package-plasmoid
```

The archive is written to `build/plasma-workbench-0.1.0.plasmoid`. CMake creates it with a fixed `SOURCE_DATE_EPOCH`, so equivalent package contents produce a reproducible archive. When `kpackagetool6` was found during configuration, verify archive installation in an isolated package root:

```bash
ctest --test-dir build -R plasmoid-archive-install --output-on-failure
```

Before packaging:

1. Validate `metadata.json` as strict JSON.
2. Remove development-only logs.
3. Run repository and report tests.
4. Test an upgrade from the previous release database.
5. Install the generated `.plasmoid` file on a clean test account.
6. Confirm that uninstalling the widget does not unexpectedly delete user task data.

## 10. Native-backend migration

Add a native backend only after the repository boundary and tests exist.

The C++ module should provide:

- `TaskModel : QAbstractListModel`.
- `TaskFilterModel : QSortFilterProxyModel`.
- `TodoRepository : QObject` backed by `Qt6::Sql`.
- Report result models.
- Explicit backup and export operations.

Store native application data under a predictable product directory. `QStandardPaths::GenericDataLocation` maps to `~/.local/share` on Linux, so a product-specific child such as `~/.local/share/workbench/` is appropriate when data must be shared with a companion application.

References:

- [KDE C++ Plasma widget API](https://develop.kde.org/docs/plasma/widget/c-api/)
- [`QStandardPaths`](https://doc.qt.io/qt-6/qstandardpaths.html)
- [`QSqlDatabase`](https://doc.qt.io/qt-6/qsqldatabase.html)

## 11. Definition of done for each change

A change is complete when:

1. The behavior matches the applicable PRD requirement.
2. Data writes are transactional when more than one row can change.
3. New persistent fields include a migration.
4. New interface text uses `i18n()`.
5. Icon-only controls have accessible names.
6. The change works in `plasmoidviewer` at minimum size and 200 percent scaling.
7. Automated tests cover new repository or report logic.
8. The installed-widget smoke test passes before a release.

