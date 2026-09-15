import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation
    Plasmoid.toolTipMainText: i18n("Work Todo")
    Plasmoid.toolTipSubText: board.activeTaskSummary
    implicitWidth: Kirigami.Units.gridUnit * 28
    implicitHeight: Kirigami.Units.gridUnit * 38
    switchWidth: Kirigami.Units.gridUnit * 18
    switchHeight: Kirigami.Units.gridUnit * 18

    fullRepresentation: TodoBoard {
        id: board
        anchors.fill: parent
        plasmoidConfiguration: plasmoid.configuration
    }

    compactRepresentation: CompactRepresentation {
        board: board
    }
}
