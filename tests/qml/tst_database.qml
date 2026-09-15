import QtQuick
import QtTest
import "../../package/contents/ui/time" as WorkTodoTime

import "../../package/contents/code/Database.js" as Database
import "../../package/contents/code/Reports.js" as Reports

TestCase {
    name: "DatabaseRepository"

    property int databaseNumber: 0

    function init() {
        databaseNumber += 1
        Database.configureDatabaseForTests("worktodo-test-" + Date.now() + "-" + databaseNumber)
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkTodoTime.TimeMath.isValidTimeZone(timezoneId)
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

        const report = Reports.weeklyReport(WorkTodoTime.TimeMath, {
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

    function test_categoryDeletionRequiresEmptyCategory() {
        const category = createCategory("Product")
        createTask(category.id, "Keep me")

        assertThrows(function() {
            Database.deleteCategory(category.id)
        }, "Move, archive, or delete")
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
        const weekly = Reports.weeklyReport(WorkTodoTime.TimeMath, {
            year: 2024,
            month: 3,
            day: 13,
            firstDayOfWeek: 1,
            timezoneId: "America/New_York"
        })
        const monthly = Reports.monthlyReport(WorkTodoTime.TimeMath, {
            year: 2024,
            month: 2,
            firstDayOfWeek: 1,
            timezoneId: "America/New_York"
        })

        compare(weekly.totalSeconds, 0)
        compare(weekly.byDate.length, 7)
        compare(monthly.totalSeconds, 0)
        compare(monthly.byDate.length, 29)
        compare(monthly.byWeek.length, 5)
    }
}
