import QtQuick
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    required property var plasmoidRoot
    implicitWidth: contentLabel.implicitWidth
    implicitHeight: contentLabel.implicitHeight

    PlasmaComponents.Label {
        id: contentLabel
        anchors.centerIn: parent
        text: root.plasmoidRoot.hasActiveSession
            ? (root.plasmoidRoot.activeSessions.length === 1
                ? root.plasmoidRoot.activeElapsedText
                : i18np("%1 timer", "%1 timers", root.plasmoidRoot.activeSessions.length))
            : i18n("Tasks")
        Accessible.name: root.plasmoidRoot.hasActiveSession
            ? root.plasmoidRoot.activeTaskSummary
            : i18n("Open Workbench")
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.plasmoidRoot.expanded = !root.plasmoidRoot.expanded
    }
}
