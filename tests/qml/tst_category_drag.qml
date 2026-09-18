import QtQuick
import QtTest

import "../../package/contents/ui" as WorkbenchUi
import "../../package/contents/ui/time" as WorkbenchTime
import "../../package/contents/code/Database.js" as Database

TestCase {
    id: testCase
    name: "CategoryDragE2E"
    when: windowShown

    property int databaseNumber: 0
    property var board: null

    QtObject {
        id: testConfiguration
        property string reportTimezone: "Etc/UTC"
        property int firstDayOfWeek: 1
        property bool use24HourTime: true
        property int unusualSessionHours: 16
        property bool showArchivedTasks: false
        property bool allowConcurrentTimers: false
        property string defaultStatusFilter: "backlog,ready,in_progress,blocked,completed"
    }

    QtObject {
        id: testPlasmoidRoot
        property var activeSessions: []
        property var activeSession: activeSessions.length > 0 ? activeSessions[0] : null
        property bool hasActiveSession: activeSessions.length > 0
        property string activeElapsedText: ""
        property string activeTaskSummary: "No active timer"
        property int elapsedRefresh: 0
        function formatSeconds(seconds) {
            const safeSeconds = Math.max(0, Math.floor(seconds))
            const hours = Math.floor(safeSeconds / 3600)
            const minutes = Math.floor((safeSeconds % 3600) / 60)
            const remainingSeconds = safeSeconds % 60
            return (hours < 10 ? "0" : "") + hours + ":"
                + (minutes < 10 ? "0" : "") + minutes + ":"
                + (remainingSeconds < 10 ? "0" : "") + remainingSeconds
        }
        function elapsedSeconds(utc) {
            return 0
        }
        function isTaskActive(taskId) {
            for (let index = 0; index < activeSessions.length; index += 1) {
                if (activeSessions[index].task_id === taskId) {
                    return true
                }
            }
            return false
        }
    }

    Item {
        id: stage
        parent: testCase.window ? testCase.window.contentItem : null
        width: 600
        height: 1000
    }

    Component {
        id: boardComponent

        WorkbenchUi.TodoBoard {
            width: 560
            height: 900
            plasmoidConfiguration: testConfiguration
            plasmoidRoot: testPlasmoidRoot
        }
    }

    function init() {
        databaseNumber += 1
        testConfiguration.allowConcurrentTimers = false
        testPlasmoidRoot.activeSessions = []
        Database.configureDatabaseForTests("workbench-category-drag-" + Date.now() + "-" + databaseNumber)
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkbenchTime.TimeMath.isValidTimeZone(timezoneId)
        })
        Database.initialize()

        const first = Database.createCategory({ name: "First", color: "#3daee9" })
        const second = Database.createCategory({ name: "Second", color: "#8ae234" })
        Database.createTask({ categoryId: first.id, title: "First task", status: "ready" })
        Database.createTask({ categoryId: first.id, title: "Second task", status: "ready" })
        Database.createTask({ categoryId: first.id, title: "Third task", status: "ready" })
        Database.createTask({ categoryId: first.id, title: "Fourth task", status: "ready" })
        Database.createTask({ categoryId: second.id, title: "Third task", status: "ready" })

        board = createTemporaryObject(boardComponent, stage)
        verify(board !== null)
        wait(100)
    }

    function cleanup() {
        if (board) {
            board.destroy()
            board = null
        }
    }

    function test_categoryDragShowsMovingFullGroupGhost() {
        const categories = Database.listCategories()
        const firstCategory = categories[0]
        const secondCategory = categories[1]
        const handle = findChild(board, "category-drag-handle-" + firstCategory.id)
        const sourceSlot = findChild(board, "category-slot-" + firstCategory.id)
        const destinationSlot = findChild(board, "category-slot-" + secondCategory.id)
        const destinationDrop = findChild(board, "category-drop-target-" + secondCategory.id)
        const destinationAfterPlaceholder = findChild(board, "category-placeholder-after-" + secondCategory.id)
        const overlay = findChild(board, "drag-overlay")
        verify(handle !== null)
        verify(sourceSlot !== null)
        verify(destinationSlot !== null)
        verify(destinationDrop !== null)
        verify(destinationAfterPlaceholder !== null)
        verify(overlay !== null)

        board.beginCategoryDrag(firstCategory, handle, sourceSlot)
        compare(board.draggedCategoryId, firstCategory.id)
        verify(board.draggedCategoryId.length > 0)
        compare(board.draggedCategoryTaskCount, 4)
        compare(board.draggedCategoryTaskPreview.length, board.categoryDragPreviewTaskLimit,
            "Category drags must not create a visual delegate for every task")
        verify(!overlay.draggingTask)
        verify(overlay.sourceItem !== null)
        tryVerify(function() { return overlay.active }, 1000)
        verify(overlay.height > handle.height, "Category ghost must contain the full category group")
        verify(destinationDrop.height >= destinationSlot.height, "A category target must cover its full task group")
        const initialY = overlay.y

        handle.y += 80
        board.updateCategoryDragPosition(handle)
        tryVerify(function() { return Math.abs(overlay.y - initialY) > 20 }, 1000)

        const lowerHalfY = destinationDrop.height * 0.75
        compare(board.categoryGroupPlacement(lowerHalfY, destinationDrop.height, secondCategory.id), "after")
        board.previewCategoryMove(firstCategory.id, secondCategory.id, "after", destinationSlot)
        compare(board.draggedCategoryTargetId, secondCategory.id)
        compare(board.draggedCategoryPreviewItem, destinationSlot)
        compare(board.draggedCategoryPlacement, "after")
        tryVerify(function() { return destinationAfterPlaceholder.height > 0 }, 1000)
        compare(board.categoryGroupPlacement(lowerHalfY, destinationDrop.height, secondCategory.id), "after",
            "Placeholder expansion must not move the drop midpoint")

        board.commitCategoryDrop(firstCategory.id, secondCategory.id, board.draggedCategoryPlacement)
        board.finishCategoryDrag()
        tryVerify(function() { return !overlay.active }, 1000)
        const reorderedCategories = Database.listCategories()
        compare(reorderedCategories[0].id, secondCategory.id)
        compare(reorderedCategories[1].id, firstCategory.id)
    }

    function test_settingsAndConcurrentTimerResolution() {
        const settings = findChild(board, "settings-page")
        const tasks = Database.listTasks({ statuses: ["ready"] })
        verify(settings !== null)
        compare(board.currentPage, "board")

        board.openSettings()
        compare(board.currentPage, "settings")
        board.closeSettings()
        compare(board.currentPage, "board")

        testConfiguration.allowConcurrentTimers = true
        Database.startTimer(tasks[0].taskId, "Etc/UTC", "2026-09-15T09:00:00.000Z", true)
        Database.startTimer(tasks[1].taskId, "Etc/UTC", "2026-09-15T09:01:00.000Z", true)
        board.reload()
        compare(board.activeSessions.length, 2)

        board.requestConcurrentTimersChange(false)
        compare(board.keepActiveTaskId, tasks[0].taskId)
        board.keepActiveTaskId = tasks[1].taskId
        board.resolveConcurrentTimerConflict()
        compare(testConfiguration.allowConcurrentTimers, false)
        const active = Database.getActiveSessions()
        compare(active.length, 1)
        compare(active[0].task_id, tasks[1].taskId)
    }

    function test_categoryTimeTogglesBetweenTodayAndTotal() {
        const category = Database.listCategories()[0]
        const task = Database.listTasks({ statuses: ["ready"] })[0]
        Database.createWorkSession({
            taskId: task.taskId,
            startedAtUtc: "2024-01-01T09:00:00.000Z",
            endedAtUtc: "2024-01-01T10:00:00.000Z",
            timezoneId: "Etc/UTC"
        })
        const endedAt = new Date(Date.now() - 60 * 1000)
        const startedAt = new Date(endedAt.getTime() - 60 * 1000)
        Database.createWorkSession({
            taskId: task.taskId,
            startedAtUtc: startedAt.toISOString(),
            endedAtUtc: endedAt.toISOString(),
            timezoneId: "Etc/UTC"
        })
        board.reload()

        const timeButton = findChild(board, "category-time-" + category.id)
        verify(timeButton !== null)
        verify(timeButton.text.indexOf("Today: ") === 0)
        const todayText = timeButton.text
        timeButton.click()
        tryVerify(function() { return timeButton.text.indexOf("Total: ") === 0 }, 1000)
        verify(timeButton.text !== todayText)
        timeButton.click()
        tryVerify(function() { return timeButton.text.indexOf("Today: ") === 0 }, 1000)
    }

    function test_categoryDailyReportUsesBoundedLazyPage() {
        const category = Database.listCategories()[0]
        const reportsPage = findChild(board, "reports-page")
        const dayLoader = findChild(board, "day-report-loader")
        const yearLoader = findChild(board, "year-report-loader")
        verify(reportsPage !== null)
        verify(dayLoader !== null)
        verify(yearLoader !== null)

        for (let iteration = 0; iteration < 10; iteration += 1) {
            board.openDailyTimeline(category.id)
            compare(board.currentPage, "reports")
            verify(reportsPage.report !== null)
            compare(dayLoader.active, true)
            tryVerify(function() { return dayLoader.item !== null }, 5000)
            const timeline = findChild(reportsPage, "daily-report-timeline")
            verify(timeline !== null)
            verify(timeline.validRange)
            compare(timeline.slotCount, 96)
            verify(timeline.hourMarkerCount <= 25)
            compare(yearLoader.item, null)

            board.closeReports()
            compare(board.currentPage, "board")
            tryCompare(dayLoader, "item", null, 5000)
            compare(reportsPage.report, null)
        }

        board.openReports(false)
        reportsPage.selectPeriod(3, true)
        tryVerify(function() { return yearLoader.item !== null }, 5000)
        compare(dayLoader.item, null)
        verify(yearLoader.item.days.length === 365 || yearLoader.item.days.length === 366)
        board.closeReports()
        tryCompare(yearLoader, "item", null, 5000)
    }

    function test_dailyReportExposesDiscoverableEditorControls() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)

        const reportsPage = findChild(board, "reports-page")
        const timeline = findChild(reportsPage, "daily-report-timeline")
        const taskLabel = findChild(reportsPage, "daily-task-label")
        const addButton = findChild(reportsPage, "report-add-session")
        const drawButton = findChild(reportsPage, "report-draw-session")
        const editor = findChild(reportsPage, "daily-session-editor")
        const taskPicker = findChild(reportsPage, "daily-task-picker")
        const scrollbar = findChild(reportsPage, "daily-timeline-scrollbar")
        verify(reportsPage !== null)
        verify(timeline !== null)
        verify(taskLabel !== null)
        verify(taskLabel.text.length > 0)
        verify(addButton !== null)
        verify(drawButton !== null)
        verify(editor !== null)
        verify(taskPicker !== null)
        verify(scrollbar !== null)
        compare(timeline.creationEnabled, false)
        compare(reportsPage.draftOpen, false)

        addButton.click()
        tryCompare(reportsPage, "draftOpen", true, 1000)
        compare(taskPicker.enabled, false)
        compare(addButton.enabled, false)
        compare(drawButton.enabled, false)
        compare(timeline.editable, false)
        verify(findChild(editor, "daily-session-start") !== null)
        verify(findChild(editor, "daily-session-end") !== null)
        verify(findChild(editor, "daily-session-save") !== null)
        const originalStart = editor.originalStartUtc
        reportsPage.beginDraft("2026-09-17T12:00:00.000Z", "2026-09-17T12:15:00.000Z", null, addButton)
        compare(editor.originalStartUtc, originalStart)
        verify(editor.errorText.indexOf("Save or cancel") >= 0)

        board.closeReports()
    }

    function test_dailyReportAddsAndSelectsExactSession() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)

        const reportsPage = findChild(board, "reports-page")
        const timeline = findChild(reportsPage, "daily-report-timeline")
        const editor = findChild(reportsPage, "daily-session-editor")
        const originalTaskId = reportsPage.selectedTaskId
        const otherTaskId = Database.listTasks({ showArchived: false }).filter(function(task) {
            return task.taskId !== originalTaskId
        })[0].taskId
        findChild(reportsPage, "report-add-session").click()
        tryCompare(reportsPage, "draftOpen", true, 1000)
        compare(reportsPage.draftTaskId, originalTaskId)

        findChild(editor, "daily-session-start").text = "09:00:00"
        findChild(editor, "daily-session-end").text = "09:15:00"
        reportsPage.selectedTaskId = otherTaskId
        findChild(editor, "daily-session-save").click()

        tryCompare(reportsPage, "draftOpen", false, 1000)
        tryCompare(reportsPage.report, "totalSeconds", 15 * 60, 1000)
        compare(timeline.segments.length, 1)
        compare(Database.listWorkSessions(originalTaskId).length, 1)
        compare(Database.listWorkSessions(otherTaskId).length, 0)

        timeline.sessionSelected(timeline.segments[0], null)
        tryCompare(reportsPage, "draftOpen", true, 1000)
        compare(editor.editing, true)
        findChild(editor, "daily-session-end").text = "09:30:00"
        findChild(editor, "daily-session-save").click()
        tryCompare(reportsPage, "draftOpen", false, 1000)
        tryCompare(reportsPage.report, "totalSeconds", 30 * 60, 1000)
        board.closeReports()
    }

    function test_dailyReportConfirmsUnusuallyLongSession() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)
        const reportsPage = findChild(board, "reports-page")
        const editor = findChild(reportsPage, "daily-session-editor")
        const taskId = reportsPage.selectedTaskId
        findChild(reportsPage, "report-add-session").click()
        tryCompare(reportsPage, "draftOpen", true, 1000)

        findChild(editor, "daily-session-start").text = "00:00:00"
        findChild(editor, "daily-session-end").text = "17:00:00"
        findChild(editor, "daily-session-save").click()
        compare(reportsPage.draftOpen, true)
        compare(reportsPage.longSessionConfirmed, true)
        compare(Database.listWorkSessions(taskId).length, 0)

        findChild(editor, "daily-session-save").click()
        tryCompare(reportsPage, "draftOpen", false, 1000)
        compare(Database.listWorkSessions(taskId).length, 1)
        board.closeReports()
    }

    function test_dailyReportDoesNotEditActiveSession() {
        const category = Database.listCategories()[0]
        const taskId = Database.listTasks({ showArchived: false }).filter(function(task) {
            return task.categoryId === category.id
        })[0].taskId
        Database.startTimer(taskId, "Etc/UTC", new Date(Date.now() - 5 * 60 * 1000).toISOString())
        board.reload()
        board.openDailyTimeline(category.id)
        const reportsPage = findChild(board, "reports-page")
        const timeline = findChild(reportsPage, "daily-report-timeline")
        const activeSegment = timeline.segments.filter(function(segment) { return segment.active })[0]
        verify(activeSegment !== undefined)

        timeline.sessionSelected(activeSegment, null)
        compare(reportsPage.draftOpen, false)
        const activeSession = Database.listWorkSessions(taskId).filter(function(session) {
            return session.id === activeSegment.sessionId
        })[0]
        compare(activeSession.ended_at_utc, null)
        Database.stopTimer(taskId, new Date().toISOString())
        board.closeReports()
    }

    function test_dailyTimelineStacksConcurrentTimersAndSupportsZoom() {
        const tasks = Database.listTasks({ statuses: ["ready"] })
        const now = Date.now()
        const timelineTitle = "Polish daily timeline"
        Database.updateTask({ id: tasks[0].taskId, title: timelineTitle })
        testConfiguration.allowConcurrentTimers = true
        const first = Database.startTimer(tasks[0].taskId, "Etc/UTC",
            new Date(now - 90 * 60 * 1000).toISOString(), true)
        const second = Database.startTimer(tasks[1].taskId, "Etc/UTC",
            new Date(now - 60 * 60 * 1000).toISOString(), true)
        board.reload()
        board.openDailyTimeline(tasks[0].categoryId)

        const reportsPage = findChild(board, "reports-page")
        const timeline = findChild(reportsPage, "daily-report-timeline")
        const firstBlock = findChild(timeline, "timeline-session-" + first.id)
        const secondBlock = findChild(timeline, "timeline-session-" + second.id)
        const firstLabel = findChild(timeline, "timeline-session-label-" + first.id)
        const zoomIn = findChild(timeline, "daily-timeline-zoom-in")
        const zoomReset = findChild(timeline, "daily-timeline-zoom-reset")
        verify(timeline !== null)
        verify(firstBlock !== null)
        verify(secondBlock !== null)
        verify(firstLabel !== null)
        verify(zoomIn !== null)
        verify(zoomReset !== null)
        compare(timeline.laneCount, 2)
        verify(firstBlock.y !== secondBlock.y)
        verify(firstBlock.x < secondBlock.x + secondBlock.width
            && secondBlock.x < firstBlock.x + firstBlock.width)
        compare(firstLabel.text, timelineTitle)
        verify(firstLabel.width >= firstLabel.implicitWidth)

        const initialSlotWidth = timeline.slotWidth
        zoomIn.click()
        tryVerify(function() { return timeline.slotWidth > initialSlotWidth }, 1000)
        verify(zoomReset.enabled)
        zoomReset.click()
        tryCompare(timeline, "zoomIndex", timeline.defaultZoomIndex, 1000)
        compare(timeline.slotWidth, initialSlotWidth)
        board.closeReports()
    }

    function test_dailyTimelineDrawModeCreatesInsteadOfPanning() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)

        const reportsPage = findChild(board, "reports-page")
        const timeline = findChild(reportsPage, "daily-report-timeline")
        const drawButton = findChild(reportsPage, "report-draw-session")
        const createArea = findChild(timeline, "daily-timeline-create-area")
        const flickable = findChild(timeline, "daily-timeline-flickable")
        verify(timeline !== null)
        verify(drawButton !== null)
        verify(createArea !== null)
        verify(flickable !== null)

        flickable.contentX = timeline.slotWidth * 8
        const contentX = flickable.contentX
        drawButton.click()
        compare(timeline.creationEnabled, true)
        compare(flickable.interactive, false)
        timeline.beginDrawing(timeline.slotWidth * 10)
        compare(createArea.dragging, true)
        timeline.updateDrawing(timeline.slotWidth * 14)
        timeline.completeDrawing(timeline.slotWidth * 14)

        tryCompare(reportsPage, "draftOpen", true, 1000)
        compare(flickable.contentX, contentX)
        verify(reportsPage.draftSegment === null)
        reportsPage.cancelDraft(false)
        board.closeReports()
    }

    function test_dailyEditorPreservesOverlappingDraft() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)
        const reportsPage = findChild(board, "reports-page")
        const editor = findChild(reportsPage, "daily-session-editor")
        const timeline = findChild(reportsPage, "daily-report-timeline")
        const taskId = reportsPage.selectedTaskId
        const base = Date.parse(reportsPage.report.startUtc) + 9 * 60 * 60 * 1000
        const first = Database.createWorkSession({ taskId: taskId,
            startedAtUtc: new Date(base).toISOString(), endedAtUtc: new Date(base + 60 * 60 * 1000).toISOString(),
            timezoneId: board.reportTimezone })
        const second = Database.createWorkSession({ taskId: taskId,
            startedAtUtc: new Date(base + 60 * 60 * 1000).toISOString(),
            endedAtUtc: new Date(base + 2 * 60 * 60 * 1000).toISOString(), timezoneId: board.reportTimezone })
        reportsPage.refresh()
        const originalTotal = reportsPage.report.totalSeconds

        reportsPage.beginDraft(new Date(base + 30 * 60 * 1000).toISOString(),
            new Date(base + 45 * 60 * 1000).toISOString(), null, null)
        editor.submit()
        compare(reportsPage.draftOpen, true)
        verify(editor.errorText.length > 0)
        compare(Database.listWorkSessions(taskId).length, 2)
        compare(reportsPage.report.totalSeconds, originalTotal)
        reportsPage.cancelDraft(false)

        const secondSegment = timeline.segments.filter(function(segment) {
            return segment.sessionId === second.id
        })[0]
        reportsPage.beginDraft(new Date(base + 30 * 60 * 1000).toISOString(),
            new Date(base + 90 * 60 * 1000).toISOString(), secondSegment, null)
        editor.submit()
        compare(reportsPage.draftOpen, true)
        verify(editor.errorText.length > 0)
        const unchanged = Database.listWorkSessions(taskId).filter(function(session) {
            return session.id === second.id
        })[0]
        compare(unchanged.started_at_utc, new Date(base + 60 * 60 * 1000).toISOString())
        compare(unchanged.ended_at_utc, new Date(base + 2 * 60 * 60 * 1000).toISOString())
        compare(reportsPage.report.totalSeconds, originalTotal)
        verify(first.id !== undefined)
        reportsPage.cancelDraft(false)
        board.closeReports()
    }

    function test_dailyEditorRequiresExplicitDstOffset() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)
        const reportsPage = findChild(board, "reports-page")
        const editor = findChild(reportsPage, "daily-session-editor")
        const originalTimezone = editor.timezoneId
        editor.timezoneId = "America/New_York"
        verify(editor.load("2026-11-01T07:00:00.000Z", "2026-11-01T08:00:00.000Z", false, "DST task"))
        findChild(editor, "daily-session-start-date").text = "2026-11-01"
        findChild(editor, "daily-session-start").text = "01:30:00"
        editor.refreshOffsetChoices()
        compare(editor.startOffsetChoices.length, 2)
        const selector = findChild(editor, "daily-session-start-offset")
        compare(selector.currentIndex, -1)

        editor.submit()
        verify(editor.errorText.indexOf("UTC offset") >= 0)
        selector.currentIndex = 0
        reportsPage.longSessionConfirmed = true
        selector.activated(0)
        compare(reportsPage.longSessionConfirmed, false)
        const selectedUtc = editor.resolvedUtc(editor.candidates("2026-11-01", "01:30:00"), selector, "start")
        compare(selectedUtc, selector.currentValue)
        const missing = editor.candidates("2026-03-08", "02:30:00")
        verify(!missing.valid || missing.utcInstants.length === 0)

        editor.timezoneId = originalTimezone
        reportsPage.cancelDraft()
        board.closeReports()
    }

    function test_reportTabsPreserveDailyCategoryScope() {
        const category = Database.listCategories()[0]
        board.openDailyTimeline(category.id)

        const reportsPage = findChild(board, "reports-page")
        const tabs = findChild(reportsPage, "report-period-tabs")
        tabs.currentIndex = 3
        tryCompare(reportsPage, "period", "year", 1000)
        compare(reportsPage.categoryId, category.id)

        tabs.currentIndex = 0
        tryCompare(reportsPage, "period", "day", 1000)
        compare(reportsPage.categoryId, category.id)
        verify(reportsPage.availableTasks.length > 0)
        const timeline = findChild(reportsPage, "daily-report-timeline")
        verify(timeline !== null)
        compare(timeline.validRange, true)
        board.closeReports()
    }
}
