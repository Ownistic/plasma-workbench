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
    Accessible.role: Accessible.Pane
    Accessible.name: i18n("Reports")

    required property var board
    property int year: 0
    property int month: 0
    property int day: 0
    property var report: null
    property var availableTasks: []
    property string selectedTaskId: ""
    property string categoryId: ""
    property var draftSegment: null
    property string draftTaskId: ""
    property bool draftOpen: false
    property bool longSessionConfirmed: false
    property real draftReturnContentY: 0
    property var draftFocusTarget: null
    property bool changingPeriod: false
    property string period: "week"
    readonly property bool monthly: period === "month"
    readonly property var chartBuckets: !report ? [] : (period === "month" && width < Kirigami.Units.gridUnit * 26
        ? report.byWeek : report.byDate)
    readonly property string title: period === "day" ? i18n("Daily report") : period === "month" ? i18n("Monthly report")
        : period === "year" ? i18n("Yearly report") : i18n("Weekly report")

    signal backRequested()

    function calendarDate() { return new Date(Date.UTC(year, month - 1, day)) }

    function inclusiveReportEndDate() {
        if (!report || !/^\d{4}-\d{2}-\d{2}$/.test(report.endDateExclusive)) {
            return ""
        }
        const date = new Date(report.endDateExclusive + "T00:00:00.000Z")
        date.setUTCDate(date.getUTCDate() - 1)
        return date.toISOString().slice(0, 10)
    }

    function periodLabel() {
        if (period === "day") {
            const date = new Date(year, month - 1, day)
            const local = WorkbenchTime.TimeMath.localPartsForUtc(new Date().toISOString(), board.reportTimezone)
            if (local.valid && local.date === year + "-" + String(month).padStart(2, "0")
                    + "-" + String(day).padStart(2, "0")) {
                return i18n("Today, %1", Qt.formatDate(date, "MMMM d"))
            }
            return Qt.formatDate(date, "dddd, MMMM d, yyyy")
        }
        if (!report) {
            return ""
        }
        return period === "year" ? report.startDate + " - " + inclusiveReportEndDate()
            : report.startDate + " - " + report.endDateExclusive
    }

    function categoryName() {
        if (!categoryId) {
            return i18n("All categories")
        }
        for (let index = 0; index < board.categories.count; index += 1) {
            const category = board.categories.get(index)
            if (category.id === categoryId) {
                return category.name
            }
        }
        return i18n("Selected category")
    }

    function taskTitle(taskId) {
        for (let index = 0; index < availableTasks.length; index += 1) {
            if (availableTasks[index].taskId === taskId) {
                return availableTasks[index].title
            }
        }
        return ""
    }

    function selectTask(taskId) {
        selectedTaskId = taskId
        for (let index = 0; index < availableTasks.length; index += 1) {
            if (availableTasks[index].taskId === taskId) {
                reportTaskPicker.currentIndex = index
                return
            }
        }
    }

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
            timezoneId: board.reportTimezone, currentUtc: new Date().toISOString(),
            categoryId: categoryId, taskId: "" }
        let nextReport = null
        try {
            if (period === "day") {
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
        cancelDraft(false)
        report = null
        availableTasks = []
        selectedTaskId = ""
        categoryId = ""
        reportError.text = ""
    }

    function selectPeriod(index, shouldRefresh) {
        cancelDraft(false)
        report = null
        changingPeriod = true
        period = ["day", "week", "month", "year"][index] || "week"
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
        cancelDraft(false)
        const date = calendarDate()
        if (period === "day") date.setUTCDate(date.getUTCDate() + direction)
        else if (period === "week") date.setUTCDate(date.getUTCDate() + direction * 7)
        else if (period === "month") date.setUTCMonth(date.getUTCMonth() + direction)
        else date.setUTCFullYear(date.getUTCFullYear() + direction)
        setCalendarDate(date)
        refresh()
    }

    function selectDay(date) {
        cancelDraft(false)
        report = null
        const pieces = date.split("-")
        year = Number(pieces[0]); month = Number(pieces[1]); day = Number(pieces[2])
        if (availableTasks.length === 0) {
            availableTasks = Database.listTasks({ showArchived: false }).filter(function(candidate) {
                return !categoryId || candidate.categoryId === categoryId
            })
            selectedTaskId = availableTasks.length > 0 ? availableTasks[0].taskId : ""
        }
        selectPeriod(0, true)
    }

    function beginDraft(startUtc, endUtc, segment, focusTarget) {
        if (segment && segment.active) {
            return
        }
        if (draftOpen) {
            dailySessionEditor.errorText = i18n("Save or cancel the current session before opening another one.")
            return
        }
        if (reportScroll.contentItem) {
            draftReturnContentY = reportScroll.contentItem.contentY
        }
        draftFocusTarget = focusTarget || null
        draftSegment = segment || null
        if (segment && segment.taskId) {
            selectTask(segment.taskId)
        }
        draftTaskId = selectedTaskId
        longSessionConfirmed = false
        const loaded = dailySessionEditor.load(startUtc, endUtc, draftSegment !== null,
            taskTitle(draftTaskId))
        draftOpen = loaded
        drawSessionButton.checked = false
        if (loaded) {
            dailySessionEditor.forceActiveFocus()
            Qt.callLater(revealDraft)
        }
    }

    function revealDraft() {
        const flickable = reportScroll.contentItem
        if (!draftOpen || !flickable) {
            return
        }
        const editorBottom = dailySessionEditor.y + dailySessionEditor.height + Kirigami.Units.largeSpacing
        if (editorBottom > flickable.contentY + flickable.height) {
            flickable.contentY = Math.min(Math.max(0, flickable.contentHeight - flickable.height),
                editorBottom - flickable.height)
        }
        dailySessionEditor.focusFirstField()
    }

    function beginDefaultDraft() {
        if (!report || !selectedTaskId) {
            reportError.text = i18n("Choose a task before adding time.")
            return
        }
        const step = 15 * 60 * 1000
        const rangeStart = Date.parse(report.startUtc)
        const rangeEnd = Date.parse(report.endUtc)
        const now = Date.now()
        let start = now >= rangeStart && now < rangeEnd
            ? Math.floor(now / step) * step : rangeStart + 9 * 60 * 60 * 1000
        start = Math.max(rangeStart, Math.min(rangeEnd - step, start))
        beginDraft(new Date(start).toISOString(), new Date(start + step).toISOString(), null,
            reportAddSession)
    }

    function cancelDraft(restoreFocus) {
        if (!draftOpen) {
            drawSessionButton.checked = false
            return
        }
        const focusTarget = draftFocusTarget
        const returnContentY = draftReturnContentY
        draftSegment = null
        draftTaskId = ""
        draftOpen = false
        longSessionConfirmed = false
        draftFocusTarget = null
        if (dailySessionEditor) {
            dailySessionEditor.errorText = ""
        }
        if (drawSessionButton) {
            drawSessionButton.checked = false
        }
        if (restoreFocus !== false) {
            Qt.callLater(function() { root.restoreAfterDraft(returnContentY, focusTarget) })
        }
    }

    function restoreAfterDraft(returnContentY, focusTarget) {
        const flickable = reportScroll.contentItem
        if (flickable) {
            flickable.contentY = Math.max(0, Math.min(returnContentY,
                Math.max(0, flickable.contentHeight - flickable.height)))
        }
        if (focusTarget && focusTarget.visible && focusTarget.enabled) {
            focusTarget.forceActiveFocus()
        } else if (reportAddSession.visible && reportAddSession.enabled) {
            reportAddSession.forceActiveFocus()
        }
    }

    function saveDraft(startUtc, endUtc) {
        try {
            const durationSeconds = (Date.parse(endUtc) - Date.parse(startUtc)) / 1000
            if (!longSessionConfirmed && durationSeconds / 3600 >= board.unusualSessionHours) {
                longSessionConfirmed = true
                dailySessionEditor.errorText = i18n("This session lasts %1. Select Save anyway to confirm.",
                    board.formatSeconds(durationSeconds))
                return
            }
            if (draftSegment) {
                if (draftSegment.active) {
                    throw new Error(i18n("Stop the active timer before editing this session."))
                }
                Database.updateWorkSession({ id: draftSegment.sessionId, startedAtUtc: startUtc,
                    endedAtUtc: endUtc, timezoneId: board.reportTimezone })
            } else {
                Database.createWorkSession({ taskId: draftTaskId, startedAtUtc: startUtc,
                    endedAtUtc: endUtc, timezoneId: board.reportTimezone })
            }
            cancelDraft()
            board.reload()
            refresh()
        } catch (error) {
            dailySessionEditor.errorText = error.message
        }
    }

    Controls.ScrollView {
        id: reportScroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            x: Kirigami.Units.largeSpacing
            width: Math.max(0, reportScroll.availableWidth - Kirigami.Units.largeSpacing * 2)
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
                text: root.periodLabel()
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
            objectName: "report-period-tabs"
            Layout.fillWidth: true
            currentIndex: 1
            onCurrentIndexChanged: {
                if (!root.changingPeriod && root.report !== null) {
                    root.cancelDraft(false)
                    root.report = null
                    root.period = ["day", "week", "month", "year"][currentIndex] || "week"
                    if (root.period === "day") {
                        if (root.availableTasks.length === 0) {
                            root.availableTasks = Database.listTasks({ showArchived: false }).filter(function(candidate) {
                                return !root.categoryId || candidate.categoryId === root.categoryId
                            })
                            root.selectedTaskId = root.availableTasks.length > 0
                                ? root.availableTasks[0].taskId : ""
                        }
                    }
                    root.refresh()
                }
            }
            PlasmaComponents.TabButton {
                objectName: "reports-day-tab"
                text: i18n("Day")
            }
            PlasmaComponents.TabButton {
                objectName: "reports-week-tab"
                text: i18n("Week")
            }
            PlasmaComponents.TabButton {
                objectName: "reports-month-tab"
                text: i18n("Month")
            }
            PlasmaComponents.TabButton {
                objectName: "reports-year-tab"
                text: i18n("Year")
            }
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: root.report ? i18n("Total: %1", root.board.formatSeconds(root.report.totalSeconds)) : ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.period === "day"

            PlasmaComponents.Label {
                objectName: "daily-scope-label"
                Layout.fillWidth: true
                text: i18n("Category: %1", root.categoryName())
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    id: dailyTaskLabel
                    objectName: "daily-task-label"
                    text: i18n("Task")
                }

                PlasmaComponents.ComboBox {
                    id: reportTaskPicker
                    objectName: "daily-task-picker"
                    Layout.fillWidth: true
                    model: root.availableTasks
                    textRole: "title"
                    valueRole: "taskId"
                    enabled: !root.draftOpen
                    Accessible.name: i18n("Task for the work session")
                    onActivated: root.selectedTaskId = currentValue
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    id: reportAddSession
                    objectName: "report-add-session"
                    text: i18n("Add session")
                    icon.name: "list-add"
                    enabled: root.selectedTaskId.length > 0 && !root.draftOpen
                    onClicked: root.beginDefaultDraft()
                }

                PlasmaComponents.Button {
                    id: drawSessionButton
                    objectName: "report-draw-session"
                    Layout.fillWidth: true
                    text: checked ? i18n("Drawing on timeline") : i18n("Draw on timeline")
                    icon.name: "draw-freehand"
                    checkable: true
                    enabled: root.selectedTaskId.length > 0 && !root.draftOpen
                    Accessible.description: i18n("Turn on drawing, then drag across quarter-hour slots.")
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: drawSessionButton.checked
                    ? i18n("Drag across the timeline to choose a start and end time. Use its scrollbar to reposition.")
                    : (root.report && root.report.totalSeconds === 0
                        ? i18n("No sessions yet. Add one precisely, or draw it on the timeline.")
                        : i18n("Scroll across the full day. Select a session to edit it."))
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }
        }

        Loader {
            id: dayLoader
            objectName: "day-report-loader"
            Layout.fillWidth: true
            Layout.preferredHeight: item ? Math.max(item.implicitHeight, Kirigami.Units.gridUnit * 6) : 0
            active: root.report !== null && root.period === "day"
            sourceComponent: Component {
                DailyTimeline {
                    objectName: "daily-report-timeline"
                    report: root.report
                    localDate: root.year + "-" + String(root.month).padStart(2, "0")
                        + "-" + String(root.day).padStart(2, "0")
                    timezoneId: root.board.reportTimezone
                    editable: !root.draftOpen
                    creationEnabled: drawSessionButton.checked && !root.draftOpen
                    formatSeconds: root.board.formatSeconds
                    onSessionCreateRequested: function(startUtc, endUtc) {
                        root.beginDraft(startUtc, endUtc, null, drawSessionButton)
                    }
                    onSessionEditRequested: function(segment, startUtc, endUtc, source) {
                        root.beginDraft(startUtc, endUtc, segment, source)
                    }
                    onSessionSelected: function(segment, source) {
                        root.beginDraft(segment.sessionStartUtc, segment.sessionEndUtc, segment, source)
                    }
                }
            }
        }

        DailySessionEditor {
            id: dailySessionEditor
            visible: root.draftOpen
            Layout.fillWidth: true
            timezoneId: root.board.reportTimezone
            formatSeconds: root.board.formatSeconds
            longConfirmationRequired: root.longSessionConfirmed
            onSaveRequested: function(startUtc, endUtc) { root.saveDraft(startUtc, endUtc) }
            onCancelRequested: root.cancelDraft()
            onDraftChanged: {
                root.longSessionConfirmed = false
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
                    endDate: root.inclusiveReportEndDate()
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
            visible: root.report && root.report.totalSeconds === 0 && root.period !== "day"
            text: i18n("No tracked work in this period")
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.report && root.report.totalSeconds > 0
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
