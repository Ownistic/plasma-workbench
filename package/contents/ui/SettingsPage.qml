import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root
    objectName: "settings-page"

    required property var board
    required property var plasmoidConfiguration
    signal backRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                text: i18n("Back")
                Accessible.name: i18n("Back to tasks")
                onClicked: root.backRequested()
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 2
                text: i18n("Settings")
            }
        }

        PlasmaComponents.CheckBox {
            id: concurrentTimers
            Layout.fillWidth: true
            text: i18n("Allow multiple timers to run at the same time")
            checked: root.plasmoidConfiguration.allowConcurrentTimers === true
            onClicked: root.board.requestConcurrentTimersChange(checked)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("When enabled, time tracked by concurrent tasks overlaps and is counted for each task in reports.")
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
