import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: root

    required property var report
    required property int year
    property real cellSize: Kirigami.Units.gridUnit * 0.72
    property var formatSeconds: function(seconds) { return Math.round(seconds / 60) + " min" }
    readonly property bool validYear: Number.isInteger(year) && year >= 1 && year <= 9999
    readonly property var days: createDays()
    readonly property real maximumSeconds: report && Array.isArray(report.byDate) && report.byDate.length > 0
        ? Math.max.apply(Math, report.byDate.map(function(day) { return day.seconds })) : 0
    implicitWidth: 54 * (cellSize + Kirigami.Units.smallSpacing)
    implicitHeight: 7 * (cellSize + Kirigami.Units.smallSpacing)
    Accessible.name: i18n("Daily tracked-time heatmap for %1", year)

    signal daySelected(string date)

    function createDays() {
        const result = []
        if (!validYear) {
            return result
        }
        const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0)
        const dayCount = leapYear ? 366 : 365
        const yearStart = Date.UTC(year, 0, 1)
        const firstDay = (new Date(yearStart).getUTCDay() + 6) % 7
        const totals = {}
        if (report && Array.isArray(report.byDate)) {
            for (let index = 0; index < report.byDate.length; index += 1) {
                totals[report.byDate[index].id] = report.byDate[index].seconds
            }
        }
        for (let index = 0; index < dayCount; index += 1) {
            const cursor = new Date(yearStart + index * 24 * 60 * 60 * 1000)
            const date = cursor.toISOString().slice(0, 10)
            result.push({ date: date, seconds: totals[date] || 0, day: (cursor.getUTCDay() + 6) % 7,
                week: Math.floor((firstDay + index) / 7) })
        }
        return result
    }

    function colorFor(seconds) {
        if (seconds <= 0 || maximumSeconds <= 0) {
            return Kirigami.Theme.alternateBackgroundColor
        }
        const level = Math.ceil(seconds / maximumSeconds * 4)
        return level === 1 ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
            : level === 2 ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
            : level === 3 ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.75)
            : Kirigami.Theme.highlightColor
    }

    Repeater {
        model: root.days
        delegate: Rectangle {
            required property var modelData
            x: modelData.week * (root.cellSize + Kirigami.Units.smallSpacing)
            y: modelData.day * (root.cellSize + Kirigami.Units.smallSpacing)
            width: root.cellSize
            height: root.cellSize
            radius: Kirigami.Units.smallSpacing
            color: root.colorFor(modelData.seconds)
            objectName: "year-day-" + modelData.date

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
