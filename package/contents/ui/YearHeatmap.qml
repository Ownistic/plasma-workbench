import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root

    required property var report
    required property string endDate
    readonly property real cellSpacing: Kirigami.Units.smallSpacing
    readonly property real maximumCellSize: Kirigami.Units.gridUnit * 0.72
    property real cellSize: Math.max(3, Math.min(maximumCellSize,
        ((width > 0 ? width : implicitWidth) - 52 * cellSpacing) / 53))
    property var formatSeconds: function(seconds) { return Math.round(seconds / 60) + " min" }
    readonly property bool validEndDate: /^\d{4}-\d{2}-\d{2}$/.test(endDate)
    readonly property var days: createDays()
    readonly property real maximumSeconds: maximumDailySeconds()
    readonly property color emptyDayColor: Kirigami.Theme.alternateBackgroundColor
    // A standalone plasmoid can expose an uninitialized Kirigami color set.
    readonly property color heatmapColor: Kirigami.Theme.highlightColor === emptyDayColor
        ? "#3daee9" : Kirigami.Theme.highlightColor
    implicitWidth: 53 * maximumCellSize + 52 * cellSpacing
    implicitHeight: 7 * (cellSize + cellSpacing)
    Accessible.name: i18n("Daily tracked-time heatmap ending %1", endDate)
    Accessible.role: Accessible.Graphic

    signal daySelected(string date)

    function maximumDailySeconds() {
        let maximum = 0
        if (!report || !report.byDate) {
            return maximum
        }
        for (let index = 0; index < report.byDate.length; index += 1) {
            maximum = Math.max(maximum, Number(report.byDate[index].seconds) || 0)
        }
        return maximum
    }

    function createDays() {
        const result = []
        if (!validEndDate) {
            return result
        }
        const lastDay = new Date(endDate + "T00:00:00.000Z")
        if (isNaN(lastDay.getTime())) {
            return result
        }
        const firstDayDate = new Date(lastDay)
        firstDayDate.setUTCDate(firstDayDate.getUTCDate() - 364)
        const firstDay = (firstDayDate.getUTCDay() + 6) % 7
        const totals = {}
        if (report && report.byDate) {
            for (let index = 0; index < report.byDate.length; index += 1) {
                totals[report.byDate[index].id] = report.byDate[index].seconds
            }
        }
        for (let index = 0; index < 365; index += 1) {
            const cursor = new Date(firstDayDate)
            cursor.setUTCDate(firstDayDate.getUTCDate() + index)
            const date = cursor.toISOString().slice(0, 10)
            result.push({ date: date, seconds: totals[date] || 0, day: (cursor.getUTCDay() + 6) % 7,
                week: Math.floor((firstDay + index) / 7) })
        }
        return result
    }

    function colorFor(seconds) {
        if (seconds <= 0 || maximumSeconds <= 0) {
            return emptyDayColor
        }
        const level = Math.ceil(seconds / maximumSeconds * 4)
        return level === 1 ? Qt.rgba(heatmapColor.r, heatmapColor.g, heatmapColor.b, 0.3)
            : level === 2 ? Qt.rgba(heatmapColor.r, heatmapColor.g, heatmapColor.b, 0.5)
            : level === 3 ? Qt.rgba(heatmapColor.r, heatmapColor.g, heatmapColor.b, 0.75)
            : heatmapColor
    }

    Repeater {
        model: root.days
        delegate: Rectangle {
            required property var modelData
            x: modelData.week * (root.cellSize + root.cellSpacing)
            y: modelData.day * (root.cellSize + root.cellSpacing)
            width: root.cellSize
            height: root.cellSize
            radius: Kirigami.Units.smallSpacing
            color: root.colorFor(modelData.seconds)
            objectName: "year-day-" + modelData.date
            Accessible.name: i18n("Tracked time on %1: %2", modelData.date,
                root.formatSeconds(modelData.seconds))
            Accessible.role: Accessible.Button

            Controls.ToolTip.visible: heatmapMouse.containsMouse
            Controls.ToolTip.text: modelData.date + ": " + root.formatSeconds(modelData.seconds)

            MouseArea {
                id: heatmapMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.daySelected(modelData.date)
            }
        }
    }
}
