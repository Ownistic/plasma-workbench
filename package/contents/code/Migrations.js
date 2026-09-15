.pragma library

const CURRENT_VERSION = 1

const migrations = [
    {
        version: 1,
        statements: [
            "CREATE TABLE IF NOT EXISTS categories (" +
                "id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, " +
                "position INTEGER NOT NULL, collapsed INTEGER NOT NULL DEFAULT 0, " +
                "created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL)",
            "CREATE UNIQUE INDEX IF NOT EXISTS categories_position_idx ON categories(position)",
            "CREATE TABLE IF NOT EXISTS tasks (" +
                "id TEXT PRIMARY KEY, category_id TEXT NOT NULL, title TEXT NOT NULL, " +
                "details TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, position INTEGER NOT NULL, " +
                "archived_at_utc TEXT, completed_at_utc TEXT, created_at_utc TEXT NOT NULL, " +
                "updated_at_utc TEXT NOT NULL, " +
                "FOREIGN KEY (category_id) REFERENCES categories(id) ON UPDATE CASCADE ON DELETE RESTRICT, " +
                "CHECK (length(trim(title)) BETWEEN 1 AND 200), " +
                "CHECK (status IN ('backlog', 'ready', 'in_progress', 'blocked', 'completed')))",
            "CREATE UNIQUE INDEX IF NOT EXISTS tasks_category_position_idx ON tasks(category_id, position)",
            "CREATE INDEX IF NOT EXISTS tasks_status_idx ON tasks(status)",
            "CREATE INDEX IF NOT EXISTS tasks_archived_status_idx ON tasks(archived_at_utc, status)",
            "CREATE TABLE IF NOT EXISTS work_sessions (" +
                "id TEXT PRIMARY KEY, task_id TEXT NOT NULL, started_at_utc TEXT NOT NULL, " +
                "ended_at_utc TEXT, timezone_id TEXT NOT NULL, manually_edited INTEGER NOT NULL DEFAULT 0, " +
                "note TEXT NOT NULL DEFAULT '', created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "FOREIGN KEY (task_id) REFERENCES tasks(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "CHECK (ended_at_utc IS NULL OR ended_at_utc >= started_at_utc))",
            "CREATE INDEX IF NOT EXISTS work_sessions_task_start_idx ON work_sessions(task_id, started_at_utc)",
            "CREATE INDEX IF NOT EXISTS work_sessions_period_idx ON work_sessions(started_at_utc, ended_at_utc)",
            "CREATE UNIQUE INDEX IF NOT EXISTS one_active_work_session_idx ON work_sessions((1)) WHERE ended_at_utc IS NULL",
            "CREATE TABLE IF NOT EXISTS status_events (" +
                "id TEXT PRIMARY KEY, task_id TEXT NOT NULL, previous_status TEXT, status TEXT NOT NULL, " +
                "occurred_at_utc TEXT NOT NULL, manually_edited INTEGER NOT NULL DEFAULT 0, " +
                "created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "FOREIGN KEY (task_id) REFERENCES tasks(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "CHECK (previous_status IS NULL OR previous_status IN ('backlog', 'ready', 'in_progress', 'blocked', 'completed')), " +
                "CHECK (status IN ('backlog', 'ready', 'in_progress', 'blocked', 'completed')))",
            "CREATE INDEX IF NOT EXISTS status_events_task_time_idx ON status_events(task_id, occurred_at_utc)"
        ]
    }
]

function apply(tx, appliedAtUtc) {
    tx.executeSql("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at_utc TEXT NOT NULL)")
    const result = tx.executeSql("SELECT COALESCE(MAX(version), 0) AS version FROM schema_migrations")
    const currentVersion = result.rows.item(0).version

    for (let index = 0; index < migrations.length; index += 1) {
        const migration = migrations[index]
        if (migration.version <= currentVersion) {
            continue
        }
        for (let statementIndex = 0; statementIndex < migration.statements.length; statementIndex += 1) {
            tx.executeSql(migration.statements[statementIndex])
        }
        tx.executeSql(
            "INSERT INTO schema_migrations (version, applied_at_utc) VALUES (?, ?)",
            [migration.version, appliedAtUtc]
        )
    }
}
