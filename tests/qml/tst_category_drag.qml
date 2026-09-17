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
}
