.pragma library

const CURRENT_VERSION = 5

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
    },
    {
        version: 2,
        statements: [
            "ALTER TABLE status_events ADD COLUMN sequence INTEGER NOT NULL DEFAULT 0",
            "UPDATE status_events SET sequence = rowid WHERE sequence = 0",
            "CREATE UNIQUE INDEX IF NOT EXISTS status_events_task_sequence_idx ON status_events(task_id, sequence)",
            "CREATE TRIGGER IF NOT EXISTS tasks_category_exists_insert " +
                "BEFORE INSERT ON tasks FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM categories WHERE id = NEW.category_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Task category does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS tasks_category_exists_update " +
                "BEFORE UPDATE OF category_id ON tasks FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM categories WHERE id = NEW.category_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Task category does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS sessions_task_exists_insert " +
                "BEFORE INSERT ON work_sessions FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Work-session task does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS sessions_task_exists_update " +
                "BEFORE UPDATE OF task_id ON work_sessions FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Work-session task does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS events_task_exists_insert " +
                "BEFORE INSERT ON status_events FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Status-event task does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS events_task_exists_update " +
                "BEFORE UPDATE OF task_id ON status_events FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Status-event task does not exist'); END"
        ]
    },
    {
        version: 3,
        statements: [
            "ALTER TABLE categories ADD COLUMN trashed_at_utc TEXT",
            "CREATE INDEX IF NOT EXISTS categories_trashed_at_idx ON categories(trashed_at_utc)"
        ]
    },
    {
        version: 4,
        statements: [
            "DROP INDEX IF EXISTS categories_position_idx",
            "CREATE UNIQUE INDEX IF NOT EXISTS categories_active_position_idx ON categories(position) WHERE trashed_at_utc IS NULL"
        ]
    },
    {
        version: 5,
        statements: [
            "ALTER TABLE tasks ADD COLUMN tracked_seconds INTEGER NOT NULL DEFAULT 0",
            "UPDATE tasks SET tracked_seconds = COALESCE((SELECT SUM(strftime('%s', ended_at_utc) - strftime('%s', started_at_utc)) FROM work_sessions WHERE task_id = tasks.id AND ended_at_utc IS NOT NULL), 0)"
        ]
    }
]

function apply(tx, appliedAtUtc) {
    tx.executeSql("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at_utc TEXT NOT NULL)")
    const applied = tx.executeSql("SELECT version FROM schema_migrations ORDER BY version")
    let currentVersion = 0
    for (let index = 0; index < applied.rows.length; index += 1) {
        const version = applied.rows.item(index).version
        if (version !== index + 1) {
            throw new Error("The database migration history is not contiguous.")
        }
        currentVersion = version
    }
    if (currentVersion > CURRENT_VERSION) {
        throw new Error("The database was created by a newer version of Work Todo.")
    }

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
