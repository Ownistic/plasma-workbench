import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.quickcharts as Charts
import "time" as WorkbenchTime

import "../code/Reports.js" as Reports

Controls.Dialog {
    id: root

    required property var board
    parent: root.board
    property bool monthly: false
    property int year: 0
    property int month: 0
    property int day: 0
    property var report: null
    readonly property var chartBuckets: !root.report ? [] : (root.monthly
        && root.width < Kirigami.Units.gridUnit * 26 ? root.report.byWeek : root.report.byDate)
    modal: true
    title: root.monthly ? i18n("Monthly report") : i18n("Weekly report")
    standardButtons: Controls.Dialog.Close
    width: Math.min(root.board.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 32)
    height: Math.min(root.board.height - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 40)

    function calendarDate() {
        return new Date(Date.UTC(root.year, root.month - 1, root.day))
    }

    function setCalendarDate(date) {
        root.year = date.getUTCFullYear()
        root.month = date.getUTCMonth() + 1
        root.day = date.getUTCDate()
    }

    function loadCurrentDate() {
        const localDate = WorkbenchTime.TimeMath.localDateForUtc(new Date().toISOString(), root.board.reportTimezone)
        const pieces = localDate.split("-")
        root.year = Number(pieces[0])
        root.month = Number(pieces[1])
        root.day = Number(pieces[2])
    }

    function refresh() {
        if (root.monthly) {
            root.report = Reports.monthlyReport(WorkbenchTime.TimeMath, {
                year: root.year,
                month: root.month,
                firstDayOfWeek: root.board.firstDayOfWeek,
                timezoneId: root.board.reportTimezone
            })
        } else {
            root.report = Reports.weeklyReport(WorkbenchTime.TimeMath, {
                year: root.year,
                month: root.month,
                day: root.day,
                firstDayOfWeek: root.board.firstDayOfWeek,
                timezoneId: root.board.reportTimezone
            })
        }
    }

    function openReport(showMonthly) {
        root.monthly = showMonthly
        root.loadCurrentDate()
        root.refresh()
        root.open()
    }

    function movePeriod(direction) {
        const date = root.calendarDate()
        if (root.monthly) {
            date.setUTCDate(1)
            date.setUTCMonth(date.getUTCMonth() + direction)
            date.setUTCDate(Math.min(root.day, new Date(Date.UTC(
                date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate()))
        } else {
            date.setUTCDate(date.getUTCDate() + (direction * 7))
        }
        root.setCalendarDate(date)
        root.refresh()
    }

    function openTaskBreakdown(date) {
        let tasks = []
        if (root.monthly && root.width < Kirigami.Units.gridUnit * 26) {
            const weekEnd = new Date(date + "T00:00:00.000Z")
            weekEnd.setUTCDate(weekEnd.getUTCDate() + 7)
            const totals = {}
            for (let index = 0; index < root.report.dailyByTask.length; index += 1) {
                const entry = root.report.dailyByTask[index]
                if (entry.date < date || entry.date >= weekEnd.toISOString().slice(0, 10)) {
                    continue
                }
                for (let taskIndex = 0; taskIndex < entry.tasks.length; taskIndex += 1) {
                    const task = entry.tasks[taskIndex]
                    if (!totals[task.id]) {
                        totals[task.id] = { id: task.id, label: task.label, seconds: 0 }
                    }
                    totals[task.id].seconds += task.seconds
                }
            }
            tasks = Object.keys(totals).map(function(id) { return totals[id] })
                .sort(function(left, right) { return right.seconds - left.seconds })
        } else {
            const matches = root.report.dailyByTask.filter(function(entry) { return entry.date === date })
            tasks = matches.length > 0 ? matches[0].tasks : []
        }
        breakdownDate.text = date
        breakdownTasks.model = tasks
        breakdownDialog.open()
    }

    contentItem: ColumnLayout {
        implicitWidth: Kirigami.Units.gridUnit * 30
        implicitHeight: Kirigami.Units.gridUnit * 34
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                Accessible.name: root.monthly ? i18n("Previous month") : i18n("Previous week")
                onClicked: root.movePeriod(-1)
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.report ? root.report.startUtc + " - " + root.report.endUtc : ""
                elide: Text.ElideMiddle
            }

            PlasmaComponents.ToolButton {
                icon.name: "go-next"
                Accessible.name: root.monthly ? i18n("Next month") : i18n("Next week")
                onClicked: root.movePeriod(1)
            }
        }

        PlasmaComponents.TabBar {
            id: periodTabs
            Layout.fillWidth: true
            currentIndex: root.monthly ? 1 : 0
            onCurrentIndexChanged: {
                const monthly = currentIndex === 1
                if (root.monthly !== monthly) {
                    root.monthly = monthly
                    root.refresh()
                }
            }

            PlasmaComponents.TabButton { text: i18n("Week") }
            PlasmaComponents.TabButton { text: i18n("Month") }
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: root.report ? i18n("Total: %1", root.board.formatSeconds(root.report.totalSeconds)) : ""
        }

        Charts.BarChart {
            id: summaryChart
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
            visible: root.report && root.report.totalSeconds > 0
            orientation: Charts.BarChart.VerticalOrientation
            spacing: Kirigami.Units.smallSpacing
            backgroundColor: Kirigami.Theme.alternateBackgroundColor

            Charts.ArraySource {
                id: reportValues
                array: root.chartBuckets.map(function(bucket) { return bucket.seconds })
            }

            nameSource: Charts.ArraySource {
                array: root.chartBuckets.map(function(bucket) { return bucket.label })
            }

            colorSource: Charts.ArraySource {
                array: root.chartBuckets.map(function() { return Kirigami.Theme.highlightColor })
            }

            Component.onCompleted: summaryChart.insertValueSource(0, reportValues)
        }

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.report && root.report.totalSeconds === 0
            text: i18n("No tracked work in this period")
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.report && root.report.totalSeconds > 0
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: root.chartBuckets

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                            text: modelData.label
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.gridUnit
                            color: Kirigami.Theme.alternateBackgroundColor
                            radius: Kirigami.Units.smallSpacing

                            Rectangle {
                                width: parent.width * modelData.seconds / root.report.totalSeconds
                                height: parent.height
                                color: Kirigami.Theme.highlightColor
                                radius: parent.radius
                            }
                        }

                        PlasmaComponents.Label {
                            text: root.board.formatSeconds(modelData.seconds)
                        }

                        TapHandler {
                            onTapped: root.openTaskBreakdown(modelData.id)
                        }
                    }
                }

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("By category")
                }

                Repeater {
                    model: root.report ? root.report.byCategory : []

                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label + ": " + root.board.formatSeconds(modelData.seconds)
                    }
                }

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: i18n("By task")
                }

                Repeater {
                    model: root.report ? root.report.byTask : []

                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label + ": " + root.board.formatSeconds(modelData.seconds)
                    }
                }
            }
        }
    }

    Controls.Dialog {
        id: breakdownDialog
        parent: root.contentItem
        modal: true
        title: i18n("Task breakdown")
        standardButtons: Controls.Dialog.Close
        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 24

            PlasmaComponents.Label {
                id: breakdownDate
                Layout.fillWidth: true
                font.bold: true
            }

            Repeater {
                id: breakdownTasks
                delegate: PlasmaComponents.Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.label + ": " + root.board.formatSeconds(modelData.seconds)
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
