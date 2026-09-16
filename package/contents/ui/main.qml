import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    toolTipMainText: i18n("Workbench")
    toolTipSubText: activeTaskSummary
    implicitWidth: Kirigami.Units.gridUnit * 28
    implicitHeight: Kirigami.Units.gridUnit * 38
    switchWidth: Kirigami.Units.gridUnit * 18
    switchHeight: Kirigami.Units.gridUnit * 18
    property var activeSessions: []
    property int elapsedRefresh: 0
    readonly property bool hasActiveSession: activeSessions.length > 0
    readonly property var activeSession: hasActiveSession ? activeSessions[0] : null
    readonly property string activeElapsedText: {
        elapsedRefresh
        return hasActiveSession ? formatSeconds(elapsedSeconds(activeSession.started_at_utc)) : ""
    }
    readonly property string activeTaskSummary: hasActiveSession
        ? (activeSessions.length === 1
            ? i18n("Tracking %1", activeElapsedText)
            : i18np("Tracking %1 task", "Tracking %1 tasks", activeSessions.length))
        : i18n("No active timer")

    function activeSessionForTask(taskId) {
        for (let index = 0; index < activeSessions.length; index += 1) {
            if (activeSessions[index].task_id === taskId) {
                return activeSessions[index]
            }
        }
        return null
    }

    function isTaskActive(taskId) {
        return activeSessionForTask(taskId) !== null
    }

    function formatSeconds(seconds) {
        const safeSeconds = Math.max(0, Math.floor(seconds))
        const hours = Math.floor(safeSeconds / 3600)
        const minutes = Math.floor((safeSeconds % 3600) / 60)
        const remainingSeconds = safeSeconds % 60
        return (hours < 10 ? "0" : "") + hours + ":"
            + (minutes < 10 ? "0" : "") + minutes + ":"
            + (remainingSeconds < 10 ? "0" : "") + remainingSeconds
    }

    function elapsedSeconds(startedAtUtc) {
        return startedAtUtc ? (Date.now() - Date.parse(startedAtUtc)) / 1000 : 0
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.hasActiveSession
        onTriggered: root.elapsedRefresh += 1
    }

    fullRepresentation: TodoBoard {
        id: board
        anchors.fill: parent
        plasmoidConfiguration: plasmoid.configuration
        plasmoidRoot: root
    }

    compactRepresentation: CompactRepresentation {
        plasmoidRoot: root
    }
}
