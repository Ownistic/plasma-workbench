# Third-party notices

Workbench dynamically links to the system-provided Qt 6 Core and QML libraries.
Qt is available under LGPL-3.0-only, GPL-2.0-only, GPL-3.0-only, or commercial
terms. The applicable Qt terms depend on the Qt distribution and licensing
option used to provide the runtime. No Qt libraries are bundled in the
Workbench archive.

Workbench imports KDE Plasma, Kirigami, and KQuickCharts QML modules from the
recipient's system. Those components are not bundled and retain their own
copyright notices and license terms. Consult the distribution's package
metadata for the exact versions and licenses installed on that system.

The dynamically linked system-library arrangement allows a recipient to use a
compatible replacement Qt library. Workbench source and build instructions are
included in the distributed `source/` directory.
