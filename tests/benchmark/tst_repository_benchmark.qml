import QtQuick
import QtQuick.LocalStorage as Sql
import QtTest

import "../../package/contents/code/Database.js" as Database
import "../../package/contents/code/Migrations.js" as Migrations
import "../../package/contents/code/Reports.js" as Reports
import "../../package/contents/ui/time" as WorkTodoTime

TestCase {
    name: "RepositoryBenchmark"

    function test_scaleTargets() {
        const name = "worktodo-benchmark-" + Date.now()
        const database = Sql.LocalStorage.openDatabaseSync(name, "1.0", "benchmark", 16 * 1024 * 1024)
        const createdAt = "2024-01-01T00:00:00.000Z"
        const digits = "WITH digits(value) AS (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)), "
        const taskSequence = "sequence(n) AS (SELECT a.value + 10 * b.value + 100 * c.value + 1000 * d.value FROM digits a CROSS JOIN digits b CROSS JOIN digits c CROSS JOIN digits d) "
        const sessionSequence = "sequence(n) AS (SELECT a.value + 10 * b.value + 100 * c.value + 1000 * d.value + 10000 * e.value FROM digits a CROSS JOIN digits b CROSS JOIN digits c CROSS JOIN digits d CROSS JOIN digits e) "
        database.transaction(function(tx) {
            Migrations.apply(tx, createdAt)
            tx.executeSql("INSERT INTO categories (id, name, color, position, collapsed, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, 0, ?, ?)",
                ["category", "Benchmark", "#3daee9", 1024, createdAt, createdAt])
            tx.executeSql(digits + taskSequence +
                "INSERT INTO tasks (id, category_id, title, details, status, position, archived_at_utc, completed_at_utc, created_at_utc, updated_at_utc) " +
                "SELECT 'task-' || n, 'category', 'Task ' || n, '', 'ready', (n + 1) * 1024, NULL, NULL, '2024-01-01T00:00:00.000Z', '2024-01-01T00:00:00.000Z' FROM sequence WHERE n < 5000")
            tx.executeSql(digits + taskSequence +
                "INSERT INTO status_events (id, task_id, previous_status, status, occurred_at_utc, sequence, manually_edited, created_at_utc, updated_at_utc) " +
                "SELECT 'event-' || n, 'task-' || n, NULL, 'ready', '2024-01-01T00:00:00.000Z', 1, 0, '2024-01-01T00:00:00.000Z', '2024-01-01T00:00:00.000Z' FROM sequence WHERE n < 5000")
            tx.executeSql(digits + sessionSequence +
                "INSERT INTO work_sessions (id, task_id, started_at_utc, ended_at_utc, timezone_id, manually_edited, note, created_at_utc, updated_at_utc) " +
                "SELECT 'session-' || n, 'task-' || (n % 5000), strftime('%Y-%m-%dT%H:%M:%fZ', '2024-01-01T00:00:00Z', '+' || (n * 15) || ' minutes'), strftime('%Y-%m-%dT%H:%M:%fZ', '2024-01-01T00:00:00Z', '+' || (n * 15) || ' minutes', '+30 seconds'), 'Etc/UTC', 0, '', '2024-01-01T00:00:00.000Z', '2024-01-01T00:00:00.000Z' FROM sequence WHERE n < 100000")
        })

        Database.configureDatabaseForTests(name)
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkTodoTime.TimeMath.isValidTimeZone(timezoneId)
        })
        const taskStart = Date.now()
        const tasks = Database.listTasks({ statuses: ["ready"] })
        const taskElapsed = Date.now() - taskStart
        compare(tasks.length, 5000)
        verify(taskElapsed < 5000, "Listing 5,000 tasks took " + taskElapsed + " ms")

        const reportStart = Date.now()
        const report = Reports.monthlyReport(WorkTodoTime.TimeMath, {
            year: 2024,
            month: 1,
            firstDayOfWeek: 1,
            timezoneId: "Etc/UTC",
            currentUtc: "2024-03-01T00:00:00.000Z"
        })
        const reportElapsed = Date.now() - reportStart
        verify(report.totalSeconds > 0)
        verify(reportElapsed < 15000, "Reporting over 100,000 sessions took " + reportElapsed + " ms")
    }
}
