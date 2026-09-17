import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.quickcharts as Charts

import "time" as WorkbenchTime
import "../code/Database.js" as Database
import "../code/Reports.js" as Reports

FocusScope {
    id: root
    objectName: "reports-view"

    required property var board
    property int year: 0
    property int month: 0
    property int day: 0
    property var report: null
    property var availableTasks: []
    property string selectedTaskId: ""
    property string categoryId: ""
    property bool changingPeriod: false
    readonly property string period: ["day", "week", "month", "year"][periodTabs.currentIndex] || "week"
    readonly property bool monthly: period === "month"
    readonly property var chartBuckets: !report ? [] : (period === "month" && width < Kirigami.Units.gridUnit * 26
        ? report.byWeek : report.byDate)
    readonly property string title: period === "day" ? i18n("Daily report") : period === "month" ? i18n("Monthly report")
        : period === "year" ? i18n("Yearly report") : i18n("Weekly report")

    signal backRequested()

    function calendarDate() { return new Date(Date.UTC(year, month - 1, day)) }

    function setCalendarDate(date) {
        year = date.getUTCFullYear()
        month = date.getUTCMonth() + 1
        day = date.getUTCDate()
    }

    function loadCurrentDate() {
        const local = WorkbenchTime.TimeMath.localPartsForUtc(new Date().toISOString(), board.reportTimezone)
        if (!local.valid) {
            reportError.text = local.error || i18n("The local date could not be determined.")
            return false
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(local.date)) {
            reportError.text = i18n("The local date could not be determined.")
            return false
        }
        const pieces = local.date.split("-")
        year = Number(pieces[0]); month = Number(pieces[1]); day = Number(pieces[2])
        return true
    }

    function refresh() {
        const input = { year: year, month: month, day: day, firstDayOfWeek: board.firstDayOfWeek,
            timezoneId: board.reportTimezone, currentUtc: new Date().toISOString() }
        let nextReport = null
        try {
            if (period === "day") {
                input.categoryId = categoryId
                input.taskId = ""
                nextReport = Reports.dailyReport(WorkbenchTime.TimeMath, input)
            }
            else if (period === "month") nextReport = Reports.monthlyReport(WorkbenchTime.TimeMath, input)
            else if (period === "year") nextReport = Reports.yearlyReport(WorkbenchTime.TimeMath, input)
            else nextReport = Reports.weeklyReport(WorkbenchTime.TimeMath, input)
            reportError.text = ""
        } catch (error) {
            reportError.text = error.message
        }
        report = nextReport
    }

    function clearReport() {
        report = null
        availableTasks = []
        selectedTaskId = ""
        categoryId = ""
        reportError.text = ""
    }

    function selectPeriod(index, shouldRefresh) {
        report = null
        changingPeriod = true
        periodTabs.currentIndex = index
        changingPeriod = false
        if (shouldRefresh) {
            refresh()
        }
    }

    function openReport(showMonthly) {
        report = null
        categoryId = ""
        if (!loadCurrentDate()) {
            return
        }
        availableTasks = []
        selectedTaskId = ""
        selectPeriod(showMonthly ? 2 : 1, true)
    }

    function openDailyReport(category, task, date) {
        categoryId = category || ""
        if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
            const parts = date.split("-")
            year = Number(parts[0]); month = Number(parts[1]); day = Number(parts[2])
        } else if (!loadCurrentDate()) {
            return
        }
        availableTasks = Database.listTasks({ showArchived: false }).filter(function(candidate) {
            return !categoryId || candidate.categoryId === categoryId
        })
        selectedTaskId = task || (availableTasks.length > 0 ? availableTasks[0].taskId : "")
        selectPeriod(0, true)
    }

    function movePeriod(direction) {
        const date = calendarDate()
        if (period === "day") date.setUTCDate(date.getUTCDate() + direction)
        else if (period === "week") date.setUTCDate(date.getUTCDate() + direction * 7)
        else if (period === "month") date.setUTCMonth(date.getUTCMonth() + direction)
        else date.setUTCFullYear(date.getUTCFullYear() + direction)
        setCalendarDate(date)
        refresh()
    }

    function selectDay(date) {
        report = null
        const pieces = date.split("-")
        year = Number(pieces[0]); month = Number(pieces[1]); day = Number(pieces[2])
        categoryId = ""
        availableTasks = Database.listTasks({ showArchived: false })
        selectedTaskId = availableTasks.length > 0 ? availableTasks[0].taskId : ""
        selectPeriod(0, true)
    }

    function createSession(startUtc, endUtc) {
        if (!selectedTaskId) {
            reportError.text = i18n("Choose a task before adding time.")
            return
        }
        try {
            Database.createWorkSession({ taskId: selectedTaskId, startedAtUtc: startUtc,
                endedAtUtc: endUtc, timezoneId: board.reportTimezone })
            board.reload()
            refresh()
        } catch (error) {
            reportError.text = error.message
        }
    }

    function editSession(segment, startUtc, endUtc) {
        try {
            Database.updateWorkSession({ id: segment.sessionId, startedAtUtc: startUtc,
                endedAtUtc: endUtc, timezoneId: board.reportTimezone })
            board.reload()
            refresh()
        } catch (error) {
            reportError.text = error.message
        }
    }

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
                text: root.title
            }
        }

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                Accessible.name: i18n("Previous %1", root.period)
                onClicked: root.movePeriod(-1)
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.report ? root.report.startDate + " - " + root.report.endDateExclusive : ""
                elide: Text.ElideMiddle
            }
            PlasmaComponents.ToolButton {
                icon.name: "go-next"
                Accessible.name: i18n("Next %1", root.period)
                onClicked: root.movePeriod(1)
            }
        }

        PlasmaComponents.TabBar {
            id: periodTabs
            Layout.fillWidth: true
            currentIndex: 1
            onCurrentIndexChanged: {
                if (!root.changingPeriod && root.report !== null) {
                    root.report = null
                    root.categoryId = ""
                    if (root.period === "day") {
                        root.availableTasks = Database.listTasks({ showArchived: false })
                        root.selectedTaskId = root.availableTasks.length > 0
                            ? root.availableTasks[0].taskId : ""
                    } else {
                        root.availableTasks = []
                        root.selectedTaskId = ""
                    }
                    root.refresh()
                }
            }
            PlasmaComponents.TabButton { text: i18n("Day") }
            PlasmaComponents.TabButton { text: i18n("Week") }
            PlasmaComponents.TabButton { text: i18n("Month") }
            PlasmaComponents.TabButton { text: i18n("Year") }
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: root.report ? i18n("Total: %1", root.board.formatSeconds(root.report.totalSeconds)) : ""
        }

        PlasmaComponents.ComboBox {
            id: reportTaskPicker
            Layout.fillWidth: true
            visible: root.period === "day"
            model: root.availableTasks
            textRole: "title"
            valueRole: "taskId"
            onActivated: root.selectedTaskId = currentValue
        }

        Loader {
            id: dayLoader
            objectName: "day-report-loader"
            Layout.fillWidth: true
            Layout.preferredHeight: item ? item.implicitHeight : 0
            active: root.report !== null && root.period === "day"
            sourceComponent: Component {
                DailyTimeline {
                    objectName: "daily-report-timeline"
                    report: root.report
                    localDate: root.year + "-" + String(root.month).padStart(2, "0")
                        + "-" + String(root.day).padStart(2, "0")
                    timezoneId: root.board.reportTimezone
                    editable: true
                    formatSeconds: root.board.formatSeconds
                    onSessionCreateRequested: function(startUtc, endUtc) { root.createSession(startUtc, endUtc) }
                    onSessionEditRequested: function(segment, startUtc, endUtc) {
                        root.editSession(segment, startUtc, endUtc)
                    }
                }
            }
        }

        PlasmaComponents.Label {
            id: reportError
            Layout.fillWidth: true
            visible: text.length > 0
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
        }

        Loader {
            id: yearLoader
            objectName: "year-report-loader"
            Layout.fillWidth: true
            Layout.preferredHeight: item ? item.implicitHeight : 0
            active: root.report !== null && root.period === "year"
            sourceComponent: Component {
                YearHeatmap {
                    objectName: "year-report-heatmap"
                    report: root.report
                    year: root.year
                    formatSeconds: root.board.formatSeconds
                    onDaySelected: function(date) { root.selectDay(date) }
                }
            }
        }

        Loader {
            id: chartLoader
            objectName: "summary-chart-loader"
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
            active: root.report !== null && (root.period === "week" || root.period === "month")
                && root.report.totalSeconds > 0
            sourceComponent: Component {
                Charts.BarChart {
                    id: summaryChart
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
            }
        }

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
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
                Kirigami.Heading { Layout.fillWidth: true; level: 4; text: i18n("By category") }
                Repeater {
                    model: root.report ? root.report.byCategory : []
                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label + ": " + root.board.formatSeconds(modelData.seconds)
                    }
                }
                Kirigami.Heading { Layout.fillWidth: true; level: 4; text: i18n("By task") }
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
}
