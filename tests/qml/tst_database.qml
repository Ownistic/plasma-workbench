import QtQuick
import QtTest
import "../../package/contents/ui/time" as WorkbenchTime

import "../../package/contents/code/Database.js" as Database
import "../../package/contents/code/Reports.js" as Reports

TestCase {
    name: "DatabaseRepository"

    property int databaseNumber: 0

    function init() {
        databaseNumber += 1
        Database.configureDatabaseForTests("workbench-test-" + Date.now() + "-" + databaseNumber)
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkbenchTime.TimeMath.isValidTimeZone(timezoneId)
        })
        Database.initialize()
    }

    function createCategory(name) {
        return Database.createCategory({ name: name, color: "#3daee9" })
    }

    function createTask(categoryId, title, status) {
        return Database.createTask({
            categoryId: categoryId,
            title: title,
            status: status || "ready"
        })
    }

    function assertThrows(callback, expectedText) {
        let thrown = false
        try {
            callback()
        } catch (error) {
            thrown = true
            verify(error.message.indexOf(expectedText) !== -1, error.message)
        }
        verify(thrown, "Expected the operation to throw")
    }

    function test_repeatedInitializationKeepsSchema() {
        const category = createCategory("Product")
        Database.initialize()

        compare(Database.listCategories().length, 1)
        compare(Database.listCategories()[0].id, category.id)
    }

    function test_taskCreationAndFiltering() {
        const category = createCategory("Product")
        const ready = createTask(category.id, "Ship first version", "ready")
        const blocked = createTask(category.id, "Wait for review", "blocked")

        const readyTasks = Database.listTasks({ statuses: ["ready"] })
        compare(readyTasks.length, 1)
        compare(readyTasks[0].taskId, ready.id)
        compare(Database.listTasks({ statuses: ["blocked"] })[0].taskId, blocked.id)
        compare(Database.listStatusEvents(ready.id).length, 1)
    }

    function test_statusHistoryReconcilesAfterCorrection() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Implement reports", "backlog")
        const firstEvent = Database.listStatusEvents(task.id)[0]
        Database.changeStatus(task.id, "ready")
        const latestEvent = Database.listStatusEvents(task.id)[0]

        Database.updateStatusEvent({
            id: firstEvent.id,
            status: "blocked",
            occurredAtUtc: "2000-01-01T08:00:00.000Z"
        })

        const events = Database.listStatusEvents(task.id)
        compare(events.length, 2)
        compare(events[1].previous_status, null)
        compare(events[0].previous_status, "blocked")
        compare(Database.getTask(task.id).status, latestEvent.status)
        verify(events[1].manually_edited)
    }

    function test_timerSwitchAndCompletionAreAtomic() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First task")
        const second = createTask(category.id, "Second task")

        Database.startTimer(first.id, "Etc/UTC", "2026-09-14T10:00:00.000Z")
        Database.startTimer(second.id, "Etc/UTC", "2026-09-14T10:30:00.000Z")
        let firstSessions = Database.listWorkSessions(first.id)
        compare(firstSessions.length, 1)
        compare(firstSessions[0].ended_at_utc, "2026-09-14T10:30:00.000Z")
        compare(Database.getActiveSession().task_id, second.id)

        Database.stopTimer(second.id, "2026-09-14T11:00:00.000Z")
        Database.changeStatus(second.id, "completed")
        compare(Database.getActiveSession(), null)
        const secondSessions = Database.listWorkSessions(second.id)
        compare(secondSessions[0].ended_at_utc, "2026-09-14T11:00:00.000Z")
        compare(Database.getTask(second.id).status, "completed")
    }

    function test_concurrentTimersCanBeStoppedIndependently() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First task")
        const second = createTask(category.id, "Second task")

        const firstSession = Database.startTimer(first.id, "Etc/UTC", "2026-09-14T10:00:00.000Z", true)
        const secondSession = Database.startTimer(second.id, "Etc/UTC", "2026-09-14T10:05:00.000Z", true)
        const active = Database.getActiveSessions()
        compare(active.length, 2)
        compare(active[0].id, firstSession.id)
        compare(active[0].taskTitle, "First task")
        compare(active[1].id, secondSession.id)
        compare(active[1].taskTitle, "Second task")

        compare(Database.startTimer(second.id, "Etc/UTC", "2026-09-14T10:10:00.000Z", true).id, secondSession.id)
        compare(Database.stopTimer(first.id, "2026-09-14T10:30:00.000Z").id, firstSession.id)
        compare(Database.getActiveSessions().length, 1)
        compare(Database.getActiveSessions()[0].id, secondSession.id)
        compare(Database.listWorkSessions(first.id)[0].ended_at_utc, "2026-09-14T10:30:00.000Z")
    }

    function test_singleTimerModeStopsConcurrentTimersAndStopExceptIsAtomic() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First task")
        const second = createTask(category.id, "Second task")
        const third = createTask(category.id, "Third task")

        Database.startTimer(first.id, "Etc/UTC", "2026-09-14T10:00:00.000Z", true)
        Database.startTimer(second.id, "Etc/UTC", "2026-09-14T10:05:00.000Z", true)
        Database.startTimer(third.id, "Etc/UTC", "2026-09-14T10:30:00.000Z")
        let active = Database.getActiveSessions()
        compare(active.length, 1)
        compare(active[0].task_id, third.id)
        compare(Database.listWorkSessions(first.id)[0].ended_at_utc, "2026-09-14T10:30:00.000Z")
        compare(Database.listWorkSessions(second.id)[0].ended_at_utc, "2026-09-14T10:30:00.000Z")

        Database.startTimer(first.id, "Etc/UTC", "2026-09-14T11:00:00.000Z", true)
        Database.startTimer(second.id, "Etc/UTC", "2026-09-14T11:05:00.000Z", true)
        const stopped = Database.stopTimersExcept(first.id, "2026-09-14T11:30:00.000Z")
        compare(stopped.length, 2)
        active = Database.getActiveSessions()
        compare(active.length, 1)
        compare(active[0].task_id, first.id)
        compare(Database.listWorkSessions(second.id)[0].ended_at_utc, "2026-09-14T11:30:00.000Z")
        compare(Database.listWorkSessions(third.id)[0].ended_at_utc, "2026-09-14T11:30:00.000Z")
    }

    function test_stopTimersExceptRejectsInactiveKeeperWithoutStoppingTimers() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First task")
        const second = createTask(category.id, "Second task")
        Database.startTimer(first.id, "Etc/UTC", "2026-09-14T10:00:00.000Z", true)
        Database.startTimer(second.id, "Etc/UTC", "2026-09-14T10:01:00.000Z", true)
        Database.stopTimer(first.id, "2026-09-14T10:02:00.000Z")

        assertThrows(function() {
            Database.stopTimersExcept(first.id, "2026-09-14T10:03:00.000Z")
        }, "no longer active")

        const active = Database.getActiveSessions()
        compare(active.length, 1)
        compare(active[0].task_id, second.id)
    }

    function test_manualSessionRejectsOverlapWithConcurrentTimer() {
        const category = createCategory("Product")
        const timerTask = createTask(category.id, "Timer task")
        const manualTask = createTask(category.id, "Manual task")
        Database.startTimer(timerTask.id, "Etc/UTC", "2026-09-14T10:00:00.000Z", true)

        assertThrows(function() {
            Database.createWorkSession({
                taskId: manualTask.id,
                startedAtUtc: "2026-09-14T10:15:00.000Z",
                endedAtUtc: "2026-09-14T10:30:00.000Z",
                timezoneId: "Etc/UTC"
            })
        }, "cannot overlap")
    }

    function test_filteredMoveUsesStableTaskIds() {
        const product = createCategory("Product")
        const operations = createCategory("Operations")
        const first = createTask(product.id, "First", "ready")
        const hidden = createTask(product.id, "Hidden", "blocked")
        const moved = createTask(product.id, "Moved", "ready")

        compare(Database.listTasks({ statuses: ["ready"] }).length, 2)
        Database.moveTask({
            taskId: moved.id,
            targetTaskId: first.id,
            targetCategoryId: product.id,
            placement: "before"
        })
        let allTasks = Database.listTasks({})
        compare(allTasks[0].taskId, moved.id)
        compare(allTasks[1].taskId, first.id)
        compare(allTasks[2].taskId, hidden.id)

        Database.moveTask({
            taskId: moved.id,
            targetCategoryId: operations.id,
            placement: "before"
        })
        allTasks = Database.listTasks({})
        compare(allTasks[0].taskId, first.id)
        compare(allTasks[1].taskId, hidden.id)
        compare(allTasks[2].taskId, moved.id)
        compare(allTasks[2].categoryId, operations.id)
    }

    function test_moveTaskCanPlaceAfterLastTaskInCategory() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First")
        const middle = createTask(category.id, "Middle")
        const last = createTask(category.id, "Last")

        Database.moveTask({
            taskId: first.id,
            targetTaskId: last.id,
            targetCategoryId: category.id,
            placement: "after"
        })

        const tasks = Database.listTasks({})
        compare(tasks.length, 3)
        compare(tasks[0].taskId, middle.id)
        compare(tasks[1].taskId, last.id)
        compare(tasks[2].taskId, first.id)
    }

    function test_moveTaskCanPlaceTaskAtEndOfAnotherCategory() {
        const source = createCategory("Source")
        const destination = createCategory("Destination")
        const sourceTask = createTask(source.id, "Source task")
        const destinationFirst = createTask(destination.id, "Destination first")
        const destinationLast = createTask(destination.id, "Destination last")

        Database.moveTask({
            taskId: sourceTask.id,
            targetTaskId: destinationLast.id,
            targetCategoryId: destination.id,
            placement: "after"
        })

        const tasks = Database.listTasks({})
        compare(tasks.length, 3)
        compare(tasks[0].taskId, destinationFirst.id)
        compare(tasks[1].taskId, destinationLast.id)
        compare(tasks[2].taskId, sourceTask.id)
        compare(tasks[2].categoryId, destination.id)
    }

    function test_moveCategoryCanPlaceAfterLastActiveCategory() {
        const first = createCategory("First")
        const middle = createCategory("Middle")
        const last = createCategory("Last")

        Database.moveCategory({
            categoryId: first.id,
            targetCategoryId: last.id,
            placement: "after"
        })

        const categories = Database.listCategories()
        compare(categories.length, 3)
        compare(categories[0].id, middle.id)
        compare(categories[1].id, last.id)
        compare(categories[2].id, first.id)
    }

    function test_rejectedTaskMoveKeepsPersistedListOrder() {
        const source = createCategory("Source")
        const destination = createCategory("Destination")
        const sourceTask = createTask(source.id, "Source task")
        const destinationFirst = createTask(destination.id, "Destination first")
        const destinationMoving = createTask(destination.id, "Destination moving")

        assertThrows(function() {
            Database.moveTask({
                taskId: destinationMoving.id,
                targetTaskId: sourceTask.id,
                targetCategoryId: destination.id,
                placement: "before"
            })
        }, "destination task does not exist")

        Database.initialize()
        const tasks = Database.listTasks({})
        compare(tasks.length, 3)
        compare(tasks[0].taskId, sourceTask.id)
        compare(tasks[1].taskId, destinationFirst.id)
        compare(tasks[2].taskId, destinationMoving.id)
    }

    function test_manualSessionsRejectGlobalOverlap() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First")
        const second = createTask(category.id, "Second")
        Database.createWorkSession({
            taskId: first.id,
            startedAtUtc: "2026-09-14T09:00:00.000Z",
            endedAtUtc: "2026-09-14T10:00:00.000Z",
            timezoneId: "Etc/UTC"
        })

        assertThrows(function() {
            Database.createWorkSession({
                taskId: second.id,
                startedAtUtc: "2026-09-14T09:30:00.000Z",
                endedAtUtc: "2026-09-14T10:30:00.000Z",
                timezoneId: "Etc/UTC"
            })
        }, "cannot overlap")
    }

    function test_weeklyReportSplitsAtLocalMidnight() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Report task")
        Database.createWorkSession({
            taskId: task.id,
            startedAtUtc: "2024-01-01T22:00:00.000Z",
            endedAtUtc: "2024-01-02T03:00:00.000Z",
            timezoneId: "Europe/Berlin"
        })

        const report = Reports.weeklyReport(WorkbenchTime.TimeMath, {
            year: 2024,
            month: 1,
            day: 2,
            firstDayOfWeek: 1,
            timezoneId: "Europe/Berlin",
            currentUtc: "2024-01-03T00:00:00.000Z"
        })
        compare(report.totalSeconds, 5 * 60 * 60)
        compare(report.byDate.length, 7)
        const firstDay = report.byDate.filter(function(day) { return day.id === "2024-01-01" })[0]
        const secondDay = report.byDate.filter(function(day) { return day.id === "2024-01-02" })[0]
        compare(firstDay.seconds, 60 * 60)
        compare(secondDay.seconds, 4 * 60 * 60)
        compare(report.byCategory[0].label, "Product")
        compare(report.byTask[0].id, task.id)
    }

    function test_dailyReportUsesLocalCalendarDay() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Report task")
        Database.createWorkSession({
            taskId: task.id,
            startedAtUtc: "2024-01-01T22:00:00.000Z",
            endedAtUtc: "2024-01-02T03:00:00.000Z",
            timezoneId: "Europe/Berlin"
        })

        const report = Reports.dailyReport(WorkbenchTime.TimeMath, {
            year: 2024,
            month: 1,
            day: 2,
            timezoneId: "Europe/Berlin",
            currentUtc: "2024-01-03T00:00:00.000Z"
        })
        compare(report.totalSeconds, 4 * 60 * 60)
        compare(report.byCategory[0].id, category.id)
        compare(report.byCategory[0].seconds, 4 * 60 * 60)
        compare(report.sessionSegments.length, 1)
        compare(report.sessionSegments[0].localDate, "2024-01-02")
        compare(report.sessionSegments[0].taskId, task.id)
    }

    function test_dailyReportFiltersCategoryBeforeAggregation() {
        const firstCategory = createCategory("Product")
        const secondCategory = createCategory("Operations")
        const firstTask = createTask(firstCategory.id, "Product task")
        const secondTask = createTask(secondCategory.id, "Operations task")
        Database.createWorkSession({
            taskId: firstTask.id,
            startedAtUtc: "2024-01-02T09:00:00.000Z",
            endedAtUtc: "2024-01-02T10:00:00.000Z",
            timezoneId: "Etc/UTC"
        })
        Database.createWorkSession({
            taskId: secondTask.id,
            startedAtUtc: "2024-01-02T10:00:00.000Z",
            endedAtUtc: "2024-01-02T12:00:00.000Z",
            timezoneId: "Etc/UTC"
        })

        const report = Reports.dailyReport(WorkbenchTime.TimeMath, {
            year: 2024,
            month: 1,
            day: 2,
            timezoneId: "Etc/UTC",
            currentUtc: "2024-01-03T00:00:00.000Z",
            categoryId: firstCategory.id
        })

        compare(report.totalSeconds, 60 * 60)
        compare(report.byCategory.length, 1)
        compare(report.byCategory[0].id, firstCategory.id)
        compare(report.byTask.length, 1)
        compare(report.byTask[0].id, firstTask.id)
        compare(report.sessionSegments.length, 1)
        compare(report.sessionSegments[0].categoryId, firstCategory.id)
    }

    function test_categoryTimeMergesOverlappingTaskSessions() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First task")
        const second = createTask(category.id, "Second task")
        Database.startTimer(first.id, "Etc/UTC", "2026-09-14T10:00:00.000Z", true)
        Database.startTimer(second.id, "Etc/UTC", "2026-09-14T10:30:00.000Z", true)
        Database.stopTimer(first.id, "2026-09-14T11:00:00.000Z")
        Database.stopTimer(second.id, "2026-09-14T11:30:00.000Z")

        const report = Reports.dailyReport(WorkbenchTime.TimeMath, {
            year: 2026,
            month: 9,
            day: 14,
            timezoneId: "Etc/UTC",
            currentUtc: "2026-09-14T12:00:00.000Z"
        })
        compare(report.totalSeconds, 2 * 60 * 60)
        compare(report.byCategory[0].seconds, 90 * 60)

        const total = Database.categoryTimeTotal(category.id, "2026-09-14T12:00:00.000Z")
        compare(total.trackedSeconds, 90 * 60)
    }

    function test_categoryTrashRetainsReportHistory() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Keep me")
        Database.createWorkSession({
            taskId: task.id,
            startedAtUtc: "2024-01-01T09:00:00.000Z",
            endedAtUtc: "2024-01-01T10:00:00.000Z",
            timezoneId: "Etc/UTC"
        })

        Database.deleteCategory(category.id)

        const trashed = Database.listTrashedCategories()
        compare(trashed.length, 1)
        compare(trashed[0].id, category.id)
        verify(trashed[0].trashed_at_utc !== null)
        compare(Database.listReportSessions("2024-01-01T00:00:00.000Z", "2024-01-02T00:00:00.000Z", "2024-01-02T00:00:00.000Z").length, 1)
    }

    function test_categoryTrashHidesNormalCategoryAndTaskLists() {
        const category = createCategory("Product")
        createTask(category.id, "Hidden task")

        Database.deleteCategory(category.id)

        compare(Database.listCategories().length, 0)
        compare(Database.listTasks({}).length, 0)
    }

    function test_trashedCategoryRejectsNewTasksAndReordering() {
        const first = createCategory("First")
        const second = createCategory("Second")
        const task = createTask(second.id, "Existing task")
        Database.deleteCategory(first.id)

        assertThrows(function() {
            Database.createTask({ categoryId: first.id, title: "Hidden task", status: "ready" })
        }, "trash")
        assertThrows(function() {
            Database.moveTask({ taskId: task.id, targetCategoryId: first.id })
        }, "trash")
    }

    function test_newAndRestoredCategoriesAvoidTrashedPositions() {
        const first = createCategory("First")
        const second = createCategory("Second")
        Database.deleteCategory(second.id)

        const third = createCategory("Third")
        Database.restoreCategory(second.id)

        const categories = Database.listCategories()
        compare(categories.length, 3)
        verify(categories[0].position !== categories[1].position)
        verify(categories[1].position !== categories[2].position)
        compare(categories[2].id, second.id)
        compare(third.id, categories[1].id)
    }

    function test_titleLimitCountsUnicodeCodePoints() {
        const category = createCategory("Product")
        const withinLimit = "😀".repeat(200)
        const task = createTask(category.id, withinLimit)
        compare(Database.getTask(task.id).title, withinLimit)

        assertThrows(function() {
            createTask(category.id, "😀".repeat(201))
        }, "between 1 and 200")
    }

    function test_restoreCategoryReturnsItAndItsTasksToNormalLists() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Restored task")
        Database.deleteCategory(category.id)

        Database.restoreCategory(category.id)

        compare(Database.listTrashedCategories().length, 0)
        compare(Database.listCategories()[0].id, category.id)
        compare(Database.listTasks({})[0].taskId, task.id)
    }

    function test_purgeExpiredTrashPermanentlyDeletesCategoryChildren() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Expired task")
        Database.createWorkSession({
            taskId: task.id,
            startedAtUtc: "2024-01-01T09:00:00.000Z",
            endedAtUtc: "2024-01-01T10:00:00.000Z",
            timezoneId: "Etc/UTC"
        })
        Database.deleteCategory(category.id)

        const purgeTime = new Date(Date.now() + 31 * 24 * 60 * 60 * 1000).toISOString()
        compare(Database.purgeExpiredTrash(purgeTime), 1)

        compare(Database.listTrashedCategories().length, 0)
        compare(Database.listWorkSessions(task.id).length, 0)
        compare(Database.listStatusEvents(task.id).length, 0)
        compare(Database.listReportSessions("2024-01-01T00:00:00.000Z", "2024-01-02T00:00:00.000Z", "2024-01-02T00:00:00.000Z").length, 0)
    }

    function test_statusChangeRejectsHistoricalTimestampAndCorrectionStopsTimer() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Correct status")

        assertThrows(function() {
            Database.changeStatus(task.id, "blocked", "2020-01-01T00:00:00.000Z")
        }, "status-history correction")

        Database.startTimer(task.id, "Etc/UTC")
        Database.changeStatus(task.id, "ready")
        const latest = Database.listStatusEvents(task.id)[0]
        Database.updateStatusEvent({
            id: latest.id,
            status: "completed",
            occurredAtUtc: "2099-01-01T00:00:00.000Z"
        })

        compare(Database.getTask(task.id).status, "completed")
        compare(Database.getActiveSession(), null)
    }

    function test_rebalanceKeepsUniqueOrderAfterExhaustingGaps() {
        const category = createCategory("Product")
        const first = createTask(category.id, "First")
        const second = createTask(category.id, "Second")

        for (let index = 0; index < 14; index += 1) {
            const moving = index % 2 === 0 ? second : first
            const target = index % 2 === 0 ? first : second
            Database.moveTask({
                taskId: moving.id,
                targetTaskId: target.id,
                targetCategoryId: category.id,
                placement: "before"
            })
        }

        const tasks = Database.listTasks({})
        compare(tasks.length, 2)
        verify(tasks[0].position < tasks[1].position)
        verify(tasks[0].taskId === first.id || tasks[0].taskId === second.id)
    }

    function test_invalidInstantsAndTimeZonesAreRejectedWithoutWrites() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Validate timestamps")

        assertThrows(function() {
            Database.startTimer(task.id, "Not/A_Timezone", "2026-09-14T09:00:00.000Z")
        }, "time zone")
        assertThrows(function() {
            Database.createWorkSession({
                taskId: task.id,
                startedAtUtc: "2026-09-14 09:00:00",
                endedAtUtc: "2026-09-14T10:00:00.000Z",
                timezoneId: "Etc/UTC"
            })
        }, "UTC ISO-8601")
        compare(Database.listWorkSessions(task.id).length, 0)
    }

    function test_timerCannotCrossFutureManualSession() {
        const category = createCategory("Product")
        const manualTask = createTask(category.id, "Manual")
        const timerTask = createTask(category.id, "Timer")
        Database.createWorkSession({
            taskId: manualTask.id,
            startedAtUtc: "2099-01-01T12:00:00.000Z",
            endedAtUtc: "2099-01-01T13:00:00.000Z",
            timezoneId: "Etc/UTC"
        })

        assertThrows(function() {
            Database.startTimer(timerTask.id, "Etc/UTC", "2099-01-01T09:00:00.000Z")
        }, "would overlap")
        compare(Database.getActiveSession(), null)
    }

    function test_saveTaskRollsBackWhenAnyFieldIsInvalid() {
        const category = createCategory("Product")
        const task = createTask(category.id, "Original title", "ready")

        assertThrows(function() {
            Database.saveTask({
                id: task.id,
                title: "Changed title",
                details: "Changed details",
                categoryId: "missing-category",
                status: "blocked"
            })
        }, "category does not exist")

        const unchanged = Database.getTask(task.id)
        compare(unchanged.title, "Original title")
        compare(unchanged.details, "")
        compare(unchanged.category_id, category.id)
        compare(unchanged.status, "ready")
    }

    function test_emptyReportsSeedAllCalendarBuckets() {
        const weekly = Reports.weeklyReport(WorkbenchTime.TimeMath, {
            year: 2024,
            month: 3,
            day: 13,
            firstDayOfWeek: 1,
            timezoneId: "America/New_York"
        })
        const monthly = Reports.monthlyReport(WorkbenchTime.TimeMath, {
            year: 2024,
            month: 2,
            firstDayOfWeek: 1,
            timezoneId: "America/New_York"
        })
        const yearly = Reports.yearlyReport(WorkbenchTime.TimeMath, {
            year: 2024,
            firstDayOfWeek: 1,
            timezoneId: "America/New_York"
        })

        compare(weekly.totalSeconds, 0)
        compare(weekly.byDate.length, 7)
        compare(monthly.totalSeconds, 0)
        compare(monthly.byDate.length, 29)
        compare(monthly.byWeek.length, 5)
        compare(yearly.totalSeconds, 0)
        compare(yearly.byDate.length, 366)
    }
}
