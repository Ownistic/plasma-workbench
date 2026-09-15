import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Kirigami.AbstractCard {
    id: root

    required property var task
    required property bool active
    required property string elapsedText
    signal openRequested()
    signal timerRequested()
    signal statusRequested(string status)

    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2

    contentItem: RowLayout {
        id: content
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.smallSpacing
            color: root.task.categoryColor
            radius: width / 2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.task.title
                font.bold: true
                elide: Text.ElideRight
                Accessible.name: i18n("Task: %1", root.task.title)
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: root.task.status.replace("_", " ")
                    color: Kirigami.Theme.disabledTextColor
                    Accessible.name: i18n("Status: %1", root.task.status.replace("_", " "))
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.active ? i18n("Tracking %1", root.elapsedText) : root.elapsedText
                    horizontalAlignment: Text.AlignRight
                    Accessible.name: root.active ? i18n("Timer active: %1", root.elapsedText) : i18n("Tracked time: %1", root.elapsedText)
                }
            }
        }

        PlasmaComponents.ToolButton {
            icon.name: root.active ? "media-playback-pause" : "media-playback-start"
            Accessible.name: root.active ? i18n("Pause timer for %1", root.task.title) : i18n("Start timer for %1", root.task.title)
            onClicked: root.timerRequested()
        }

        PlasmaComponents.ToolButton {
            icon.name: "document-edit"
            Accessible.name: i18n("Open details for %1", root.task.title)
            onClicked: root.openRequested()
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: function(eventPoint, button) {
            if (eventPoint.position.x < root.width - Kirigami.Units.gridUnit * 5) {
                root.openRequested()
            }
        }
    }
}
