import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: root

    required property var board
    implicitWidth: contentLabel.implicitHeight
    implicitHeight: contentLabel.implicitHeight

    PlasmaComponents.Label {
        id: contentLabel
        anchors.centerIn: parent
        text: root.board.hasActiveSession ? root.board.activeElapsedText : i18n("Tasks")
        Accessible.name: root.board.hasActiveSession
            ? i18n("Active timer: %1", root.board.activeElapsedText)
            : i18n("Open Work Todo")
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Plasmoid.expanded = !Plasmoid.expanded
    }
}
