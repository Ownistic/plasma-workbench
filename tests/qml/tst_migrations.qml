import QtQuick
import QtQuick.LocalStorage as Sql
import QtTest

import "../../package/contents/code/Migrations.js" as Migrations

TestCase {
    name: "Migrations"

    function test_versionOneMigratesToCurrentSchema() {
        const database = Sql.LocalStorage.openDatabaseSync("workbench-migration-" + Date.now(), "1.0", "migration test", 1024 * 1024)
        database.transaction(function(tx) {
            tx.executeSql("CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, position INTEGER NOT NULL, collapsed INTEGER NOT NULL DEFAULT 0, created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL)")
            tx.executeSql("CREATE TABLE tasks (id TEXT PRIMARY KEY, category_id TEXT NOT NULL, title TEXT NOT NULL, details TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, position INTEGER NOT NULL, archived_at_utc TEXT, completed_at_utc TEXT, created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL)")
            tx.executeSql("CREATE TABLE work_sessions (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, started_at_utc TEXT NOT NULL, ended_at_utc TEXT, timezone_id TEXT NOT NULL, manually_edited INTEGER NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL)")
            tx.executeSql("CREATE TABLE status_events (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, previous_status TEXT, status TEXT NOT NULL, occurred_at_utc TEXT NOT NULL, manually_edited INTEGER NOT NULL DEFAULT 0, created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL)")
            tx.executeSql("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at_utc TEXT NOT NULL)")
            tx.executeSql("INSERT INTO schema_migrations (version, applied_at_utc) VALUES (1, '2026-01-01T00:00:00.000Z')")

            Migrations.apply(tx, "2026-01-02T00:00:00.000Z")

            const versions = tx.executeSql("SELECT version FROM schema_migrations ORDER BY version")
            compare(versions.rows.length, 6)
            compare(versions.rows.item(5).version, 6)
            const categoryColumns = tx.executeSql("PRAGMA table_info(categories)")
            let hasTrashColumn = false
            for (let index = 0; index < categoryColumns.rows.length; index += 1) {
                hasTrashColumn = hasTrashColumn || categoryColumns.rows.item(index).name === "trashed_at_utc"
            }
            verify(hasTrashColumn)
            const eventColumns = tx.executeSql("PRAGMA table_info(status_events)")
            let hasSequenceColumn = false
            for (let index = 0; index < eventColumns.rows.length; index += 1) {
                hasSequenceColumn = hasSequenceColumn || eventColumns.rows.item(index).name === "sequence"
            }
            verify(hasSequenceColumn)
            const taskColumns = tx.executeSql("PRAGMA table_info(tasks)")
            let hasTrackedSecondsColumn = false
            for (let index = 0; index < taskColumns.rows.length; index += 1) {
                hasTrackedSecondsColumn = hasTrackedSecondsColumn || taskColumns.rows.item(index).name === "tracked_seconds"
            }
            verify(hasTrackedSecondsColumn)
            const activeTimerIndex = tx.executeSql("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'one_active_work_session_idx'")
            compare(activeTimerIndex.rows.length, 0)
        })
    }
}
