# Work Todo Plasmoid documentation

This documentation set defines a KDE Plasma 6 desktop widget for personal work organization, task status tracking, and time reporting.

## Documents

- [PRD.md](PRD.md): Product requirements, scope, user flows, acceptance criteria, and release plan.
- [KDE_PLASMA_API.md](docs/KDE_PLASMA_API.md): Plasma 6, Kirigami, KConfig, and KQuickCharts APIs relevant to the widget.
- [QT_QML_API.md](docs/QT_QML_API.md): Qt Quick models, delegates, drag-and-drop, timers, and SQLite APIs.
- [PERSISTENCE_AND_REPORTING.md](docs/PERSISTENCE_AND_REPORTING.md): Database schema, invariants, migrations, time calculations, and report behavior.
- [DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md): CachyOS setup, project layout, installation, testing, debugging, and packaging.
- [REFERENCES.md](docs/REFERENCES.md): Annotated primary references and compatibility notes.

## Recommended implementation

Build version 1 as a pure QML Plasma package:

- `PlasmoidItem` hosts the desktop widget.
- Plasma Components and Kirigami provide the interface.
- `QtQuick.LocalStorage` stores application data in SQLite.
- KConfig stores widget preferences only.
- KQuickCharts renders weekly and monthly reports.

Keep database access behind a repository module. This boundary permits a later migration to a Qt/C++ backend without rewriting the interface.

## Working product name

The documents use **Work Todo Plasmoid** as a working name. The final widget name and reverse-domain plugin identifier remain product decisions.

