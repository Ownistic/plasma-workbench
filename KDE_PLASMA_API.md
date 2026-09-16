# KDE Plasma 6 API reference for Workbench

This document summarizes the KDE APIs required by Workbench. It is an implementation reference, not a replacement for the linked upstream documentation.

## 1. Plasma widget package

A Plasma desktop widget is a Plasma applet package. KDE also uses the terms **widget** and **plasmoid** for this package type.

Minimum `metadata.json` structure:

```json
{
  "KPlugin": {
    "Authors": [
      {
        "Name": "Christian Espinoza"
      }
    ],
    "Category": "Utilities",
    "Description": "Organize work tasks and track work time.",
    "Icon": "view-task",
    "Id": "com.example.workbench",
    "License": "LGPL-3.0-or-later",
    "Name": "Workbench",
    "Version": "0.1.0"
  },
  "KPackageStructure": "Plasma/Applet",
  "X-Plasma-API-Minimum-Version": "6.0"
}
```

Replace `com.example.workbench` before implementation. The directory installed under the Plasma applet location must match `KPlugin.Id`.

Plasma 6 requirements:

- Set `KPackageStructure` to `Plasma/Applet`.
- Set `X-Plasma-API-Minimum-Version` to `6.0` or the actual minimum supported Plasma 6 version.
- Name the entry point `contents/ui/main.qml`.
- Do not add the removed `X-Plasma-MainScript` or `X-Plasma-API` keys.
- Use `metadata.json`, not `metadata.desktop`.

References:

- [Plasma widget setup](https://develop.kde.org/docs/plasma/widget/setup/)
- [Porting Plasmoids to KF6](https://develop.kde.org/docs/plasma/widget/porting_kf6/)
- [KPluginMetaData API](https://api.kde.org/kpluginmetadata.html)

## 2. `PlasmoidItem`

Import:

```qml
import org.kde.plasma.plasmoid
```

The root object of a Plasma 6 widget must be `PlasmoidItem`. `PlasmoidItem` represents the QML interface to the Plasma applet instance.

Relevant properties:

| Property | Use in this product |
| --- | --- |
| `compactRepresentation` | Define the small representation used in a panel or constrained placement. |
| `fullRepresentation` | Define the task board displayed on the desktop or in an expanded popup. |
| `preferredRepresentation` | Request the full representation for desktop use. |
| `switchWidth` | Control the width at which Plasma changes representations. |
| `switchHeight` | Control the height at which Plasma changes representations. |
| `activationTogglesExpanded` | Control whether activation opens or closes the full representation. |
| `toolTipMainText` | Provide the widget name in the compact tooltip. |
| `toolTipSubText` | Display the active task or today’s tracked time. |

Recommended entry-point pattern:

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    width: Kirigami.Units.gridUnit * 28
    height: Kirigami.Units.gridUnit * 38

    fullRepresentation: TodoBoard {
        anchors.fill: parent
    }
}
```

The project must test this exact syntax against the installed Plasma version because KDE examples span several Plasma generations.

Reference: [Plasma widget setup and representations](https://develop.kde.org/docs/plasma/widget/setup/)

## 3. Applet properties and environment

Importing `org.kde.plasma.plasmoid` exposes the lowercase `plasmoid` context property. The context property represents the underlying `Plasma::Applet`.

Relevant values:

| API | Use |
| --- | --- |
| `plasmoid.formFactor` | Detect planar, horizontal, or vertical form factors. |
| `plasmoid.location` | Detect desktop-like or panel-edge placement. |
| `plasmoid.configuration` | Read and write declared widget preferences. |
| `Plasmoid.status` | Communicate active or passive state when the installed Plasma version supports the desired behavior. |

Use form-factor checks to simplify a panel representation. Do not use form-factor checks as a substitute for responsive layouts.

References:

- [Widget properties](https://develop.kde.org/docs/plasma/widget/properties/)
- [Plasma 6 applet API separation](https://develop.kde.org/docs/plasma/widget/porting_kf6/)

## 4. Plasma Components

Import:

```qml
import org.kde.plasma.components as PlasmaComponents
```

Plasma Components provide controls styled for the Plasma shell. Use these components inside the widget when a control should match other desktop widgets.

Recommended types:

| Type | Product use |
| --- | --- |
| `Button` | Primary text actions such as Create task or Save. |
| `ToolButton` | Compact icon actions such as Start timer or Open reports. |
| `RoundButton` | Optional prominent timer action. |
| `Label` | Normal card and summary text. |
| `TextField` | Task title and short filter input. |
| `TextArea` | Task description and work-session notes. |
| `ComboBox` | Category, status, and timezone selection. |
| `CheckBox` | Multi-status filter selection. |
| `TabBar` and `TabButton` | Tasks, Week, and Month navigation if tabs fit the final design. |
| `StackView` | Internal navigation between the list, details, and reports. |
| `Dialog` | Create, edit, confirmation, and manual-correction workflows. |
| `ScrollView` | Scrollable detail forms. |
| `Menu` and `MenuItem` | Secondary card and category actions. |

Avoid combining Plasma Components and generic Qt Quick Controls for equivalent controls in the same surface unless an API is missing.

Reference: [Plasma Components QML module](https://api.kde.org/org-kde-plasma-components-qmlmodule.html)

## 5. Plasma Extras

Import:

```qml
import org.kde.plasma.extras as PlasmaExtras
```

Useful types include:

| Type | Product use |
| --- | --- |
| `Heading` | Product and report headings. |
| `ListSectionHeader` | Category headers in a Plasma-native grouped list. |
| `SearchField` | Optional title or description search. |
| `PlaceholderMessage` | Empty task lists and empty reports. |

The category header needs a custom color indicator. Wrap or compose the standard section-header style instead of replacing all Plasma styling with a custom rectangle.

Reference: [Plasma Extras API files in libplasma](https://archlinux.org/packages/extra/x86_64/libplasma/files/)

## 6. Kirigami

Import:

```qml
import org.kde.kirigami as Kirigami
```

Kirigami supplies layout metrics, cards, icons, theme colors, and form patterns.

Recommended APIs:

| API | Product use |
| --- | --- |
| `Kirigami.AbstractCard` | Custom task card with a category-color strip and timer controls. |
| `Kirigami.Card` | Standard card when the standard header and content layout is sufficient. |
| `Kirigami.Heading` | Section and dialog headings. |
| `Kirigami.Icon` | Theme-aware icons. |
| `Kirigami.Units.gridUnit` | Base responsive dimensions. |
| `Kirigami.Units.largeSpacing` | Standard spacing between sections. |
| `Kirigami.Theme.*` | Theme-aware text, background, highlight, and negative colors. |
| `Kirigami.FormLayout` | Widget configuration pages and task edit forms. |
| `Kirigami.InlineMessage` | Validation or recovery messages that must remain visible. |

An `AbstractCard` supplies card styling while permitting a fully custom content layout. Set accessible text and click feedback when the entire card opens details.

References:

- [Kirigami `AbstractCard`](https://api.kde.org/qml-org-kde-kirigami-abstractcard.html)
- [Kirigami API index](https://api.kde.org/kirigami-index.html)
- [KDE Human Interface Guidelines](https://develop.kde.org/hig/)

## 7. KConfig and `plasmoid.configuration`

KConfig stores widget preferences in Plasma’s applet configuration file. Define keys in `contents/config/main.xml`.

Example:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0
      http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
    <kcfgfile name=""/>
    <group name="General">
        <entry name="firstDayOfWeek" type="Int">
            <default>1</default>
        </entry>
        <entry name="reportTimezone" type="String">
            <default></default>
        </entry>
        <entry name="showArchivedTasks" type="Bool">
            <default>false</default>
        </entry>
        <entry name="use24HourTime" type="Bool">
            <default>true</default>
        </entry>
    </group>
</kcfg>
```

Read values from the widget:

```qml
property string reportTimezone: plasmoid.configuration.reportTimezone
```

Use KConfig for preferences only. Do not store tasks, descriptions, status history, work sessions, or ordering data in `plasmoid.configuration`.

Configuration pages consist of:

- `contents/config/main.xml` for the schema.
- `contents/config/config.qml` for configuration categories.
- One QML file for each configuration page.

Reference: [Plasma widget configuration](https://develop.kde.org/docs/plasma/widget/configuration/)

## 8. KQuickCharts

Import:

```qml
import org.kde.quickcharts as Charts
```

Use `Charts.BarChart` for weekly and monthly work-time reports.

Relevant APIs:

| API | Use |
| --- | --- |
| `Charts.BarChart` | Daily or weekly tracked-time bars. |
| `Charts.ModelSource` | Read values from a QML or C++ model role. |
| `Charts.ArraySource` | Render small calculated arrays directly. |
| `colorSource` | Apply category or series colors. |
| `nameSource` | Provide names for chart series. |
| `valueSources` | Provide one or more data series. |
| `xRange` and `yRange` | Set chart ranges when automatic ranges are unsuitable. |
| `stacked` | Stack category series in report bars. |

Example shape:

```qml
Charts.BarChart {
    valueSources: [
        Charts.ModelSource {
            model: reportModel
            roleName: "seconds"
        }
    ]
    colorSource: Charts.ArraySource {
        array: [Kirigami.Theme.highlightColor]
    }
}
```

KQuickCharts is a separate runtime dependency on Arch-based systems. The interface should show a textual report if the project later decides to make chart support optional.

References:

- [KQuickCharts overview](https://api.kde.org/kquickcharts-index.html)
- [`BarChart` QML type](https://api.kde.org/qml-org-kde-quickcharts-barchart.html)
- [KQuickCharts Arch package](https://archlinux.org/packages/extra/x86_64/kquickcharts/)

## 9. Internationalization

Wrap user-facing strings in KDE’s `i18n()` function:

```qml
PlasmaComponents.Button {
    text: i18n("Create task")
}
```

Use double-quoted string literals in `i18n()` calls because KDE’s extraction tooling scans those calls.

Reference: [Plasma widget translations and i18n](https://develop.kde.org/docs/plasma/widget/translations-i18n/)

## 10. Native C++ extension boundary

KDE supports private C++ QML extensions when the widget requires advanced models, file I/O, or native libraries.

A later backend can expose:

- A `QAbstractListModel` task model.
- A `QSortFilterProxyModel` status-filter model.
- A `QObject` repository backed by `Qt6::Sql`.
- Export and backup operations.
- A shared singleton for multiple widget instances.

Compiled Plasma widgets require distribution through a system package such as an Arch package or AUR package. KDE’s documentation states that the KDE Store does not distribute widgets that require compilation.

Reference: [KDE C++ API for Plasma widgets](https://develop.kde.org/docs/plasma/widget/c-api/)

## 11. Compatibility warnings

- Many online examples target Plasma 5 and use versioned Qt 5 imports.
- Plasma 6 requires `PlasmoidItem` as the QML root.
- Plasma 6 removed `X-Plasma-MainScript` and `X-Plasma-API` from package metadata.
- KDE’s C++ widget documentation still contains some Qt 5 and KF5 sample code. Convert those samples to the installed Qt 6 and KF6 APIs before use.
- Private KDE QML modules can change without compatibility guarantees. Do not depend on another widget’s `org.kde.plasma.private.*` module.
- Verify the installed Plasma and Qt versions before selecting a minimum supported version.

