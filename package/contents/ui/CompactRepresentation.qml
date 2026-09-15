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
        text: root.plasmoidRoot.hasActiveSession ? root.plasmoidRoot.activeElapsedText : i18n("Tasks")
        Accessible.name: root.plasmoidRoot.hasActiveSession
            ? i18n("Active timer: %1", root.plasmoidRoot.activeElapsedText)
            : i18n("Open Work Todo")
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.plasmoidRoot.expanded = !root.plasmoidRoot.expanded
    }
}
