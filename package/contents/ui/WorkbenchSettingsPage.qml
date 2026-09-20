import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root
    objectName: "workbench-settings-page"

    required property var board
    signal backRequested()

    readonly property var planeBinding: board.selectedWorkspaceProvider
    readonly property var planeConfig: planeBinding && planeBinding.config ? planeBinding.config : ({})

    Controls.ScrollView {
        id: pageScroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            x: Kirigami.Units.largeSpacing
            y: Kirigami.Units.largeSpacing
            width: Math.max(0, pageScroll.availableWidth - Kirigami.Units.largeSpacing * 2)
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                text: i18n("Back")
                Accessible.name: i18n("Back to %1 workbench", root.board.selectedWorkspaceName)
                onClicked: root.backRequested()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: i18n("%1 workbench", root.board.selectedWorkspaceName)
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("Workbench settings")
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }

            RowLayout {
            objectName: "workbench-connection-summary"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                source: root.planeBinding ? "network-connect" : "folder"
                color: root.planeBinding
                    ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents.Label {
                    objectName: "workbench-connection-state"
                    font.bold: true
                    text: root.planeBinding ? i18n("Connected to Plane") : i18n("Local workbench")
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.disabledTextColor
                    text: root.planeBinding
                        ? i18n("Plane workspace: %1. Category mappings and sync apply only here.",
                            root.planeConfig.workspace || i18n("not set"))
                        : i18n("Tasks, categories, and time remain local unless you add an optional provider connection.")
                }
            }
        }

            WorkflowStatusSettings {
                Layout.fillWidth: true
                board: root.board
            }

            PlaneSettings {
                Layout.fillWidth: true
                board: root.board
            }

        }
    }
}
