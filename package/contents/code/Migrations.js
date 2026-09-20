.pragma library

const CURRENT_VERSION = 11

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
    },
    {
        version: 6,
        statements: [
            "DROP INDEX IF EXISTS one_active_work_session_idx"
        ]
    },
    {
        version: 7,
        statements: [
            "CREATE TABLE IF NOT EXISTS external_tasks (" +
                "provider TEXT NOT NULL, remote_id TEXT NOT NULL, task_id TEXT NOT NULL, " +
                "remote_key TEXT NOT NULL, remote_url TEXT NOT NULL, project_id TEXT, " +
                "remote_updated_at TEXT, last_local_updated_at TEXT NOT NULL, " +
                "last_synced_at TEXT NOT NULL, sync_state TEXT NOT NULL DEFAULT 'in_sync', " +
                "remote_payload_json TEXT NOT NULL DEFAULT '{}', " +
                "PRIMARY KEY (provider, remote_id), UNIQUE (task_id), " +
                "FOREIGN KEY (task_id) REFERENCES tasks(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "CHECK (sync_state IN ('in_sync', 'pending_push', 'conflict'))) ",
            "CREATE INDEX IF NOT EXISTS external_tasks_provider_key_idx ON external_tasks(provider, remote_key)",
            "CREATE TRIGGER IF NOT EXISTS external_tasks_task_exists_insert " +
                "BEFORE INSERT ON external_tasks FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'External task does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS external_tasks_task_exists_update " +
                "BEFORE UPDATE OF task_id ON external_tasks FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'External task does not exist'); END"
        ]
    },
    {
        version: 8,
        statements: [
            "CREATE TABLE IF NOT EXISTS workspaces (" +
                "id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL, " +
                "created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "CHECK (length(trim(name)) BETWEEN 1 AND 100))",
            "CREATE UNIQUE INDEX IF NOT EXISTS workspaces_position_idx ON workspaces(position)",
            "INSERT OR IGNORE INTO workspaces (id, name, position, created_at_utc, updated_at_utc) " +
                "SELECT 'workspace-4leaflabs', '4leaflabs', 1024, ?, ? " +
                "WHERE EXISTS (SELECT 1 FROM categories WHERE lower(name) = '4leaflabs')",
            "INSERT OR IGNORE INTO workspaces (id, name, position, created_at_utc, updated_at_utc) " +
                "SELECT 'workspace-personal', 'Personal', 2048, ?, ? " +
                "WHERE EXISTS (SELECT 1 FROM categories WHERE lower(name) = 'personal')",
            "INSERT OR IGNORE INTO workspaces (id, name, position, created_at_utc, updated_at_utc) " +
                "SELECT 'workspace-default', 'Workspace', 1024, ?, ? WHERE NOT EXISTS (SELECT 1 FROM workspaces)",
            "ALTER TABLE categories ADD COLUMN workspace_id TEXT",
            "UPDATE categories SET workspace_id = CASE " +
                "WHEN lower(name) = '4leaflabs' AND EXISTS (SELECT 1 FROM workspaces WHERE id = 'workspace-4leaflabs') THEN 'workspace-4leaflabs' " +
                "WHEN lower(name) = 'personal' AND EXISTS (SELECT 1 FROM workspaces WHERE id = 'workspace-personal') THEN 'workspace-personal' " +
                "ELSE (SELECT id FROM workspaces ORDER BY position, id LIMIT 1) END",
            "DROP INDEX IF EXISTS categories_active_position_idx",
            "CREATE UNIQUE INDEX IF NOT EXISTS categories_workspace_position_idx ON categories(workspace_id, position) WHERE trashed_at_utc IS NULL",
            "CREATE INDEX IF NOT EXISTS categories_workspace_idx ON categories(workspace_id)",
            "CREATE TRIGGER IF NOT EXISTS categories_workspace_required_insert " +
                "BEFORE INSERT ON categories FOR EACH ROW WHEN NEW.workspace_id IS NULL OR NOT EXISTS " +
                "(SELECT 1 FROM workspaces WHERE id = NEW.workspace_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Category workspace does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS categories_workspace_required_update " +
                "BEFORE UPDATE OF workspace_id ON categories FOR EACH ROW WHEN NEW.workspace_id IS NULL OR NOT EXISTS " +
                "(SELECT 1 FROM workspaces WHERE id = NEW.workspace_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Category workspace does not exist'); END"
        ]
    },
    {
        version: 9,
        statements: [
            "CREATE TABLE IF NOT EXISTS workspace_providers (" +
                "workspace_id TEXT PRIMARY KEY, provider TEXT NOT NULL, connection_id TEXT, config_json TEXT NOT NULL DEFAULT '{}', " +
                "created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS provider_project_mappings (" +
                "category_id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, provider TEXT NOT NULL, remote_project_id TEXT NOT NULL, " +
                "remote_project_name TEXT NOT NULL DEFAULT '', created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "FOREIGN KEY (category_id) REFERENCES categories(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "UNIQUE (workspace_id, provider, remote_project_id))",
            "CREATE INDEX IF NOT EXISTS provider_project_mappings_workspace_idx ON provider_project_mappings(workspace_id, provider)",
            "CREATE TABLE IF NOT EXISTS provider_state_mappings (" +
                "workspace_id TEXT NOT NULL, provider TEXT NOT NULL, remote_state_id TEXT NOT NULL, local_status TEXT NOT NULL, " +
                "is_outbound INTEGER NOT NULL DEFAULT 0, remote_state_name TEXT NOT NULL DEFAULT '', created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "PRIMARY KEY (workspace_id, provider, remote_state_id), " +
                "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "CHECK (local_status IN ('backlog', 'ready', 'in_progress', 'blocked', 'completed')), " +
                "CHECK (is_outbound IN (0, 1)))",
            "CREATE UNIQUE INDEX IF NOT EXISTS provider_state_mappings_outbound_idx ON provider_state_mappings(workspace_id, provider, local_status) WHERE is_outbound = 1",
            "CREATE TABLE IF NOT EXISTS provider_members (" +
                "workspace_id TEXT NOT NULL, provider TEXT NOT NULL, project_id TEXT NOT NULL, member_id TEXT NOT NULL, " +
                "member_name TEXT NOT NULL DEFAULT '', member_email TEXT NOT NULL DEFAULT '', member_payload_json TEXT NOT NULL DEFAULT '{}', " +
                "updated_at_utc TEXT NOT NULL, PRIMARY KEY (workspace_id, provider, project_id, member_id), " +
                "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS provider_task_links (" +
                "task_id TEXT PRIMARY KEY, provider TEXT NOT NULL, remote_id TEXT, remote_key TEXT NOT NULL DEFAULT '', remote_url TEXT NOT NULL DEFAULT '', " +
                "project_id TEXT, remote_updated_at TEXT, remote_revision TEXT, last_local_updated_at TEXT NOT NULL, last_synced_at TEXT, " +
                "sync_state TEXT NOT NULL DEFAULT 'in_sync', sync_error TEXT, assignee_ids_json TEXT NOT NULL DEFAULT '[]', " +
                "managed_baseline_json TEXT NOT NULL DEFAULT '{}', remote_payload_json TEXT NOT NULL DEFAULT '{}', " +
                "created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "FOREIGN KEY (task_id) REFERENCES tasks(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "CHECK (sync_state IN ('in_sync', 'pending_create', 'pending_push', 'conflict', 'error')))",
            "CREATE UNIQUE INDEX IF NOT EXISTS provider_task_links_provider_remote_idx ON provider_task_links(provider, remote_id) WHERE remote_id IS NOT NULL",
            "CREATE INDEX IF NOT EXISTS provider_task_links_sync_idx ON provider_task_links(provider, sync_state)",
            "INSERT OR IGNORE INTO provider_task_links (task_id, provider, remote_id, remote_key, remote_url, project_id, remote_updated_at, last_local_updated_at, last_synced_at, sync_state, remote_payload_json, created_at_utc, updated_at_utc) " +
                "SELECT task_id, provider, remote_id, remote_key, remote_url, project_id, remote_updated_at, last_local_updated_at, last_synced_at, sync_state, remote_payload_json, last_synced_at, last_synced_at FROM external_tasks",
            "CREATE TRIGGER IF NOT EXISTS provider_task_links_task_exists_insert " +
                "BEFORE INSERT ON provider_task_links FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Provider task does not exist'); END",
            "CREATE TRIGGER IF NOT EXISTS provider_task_links_task_exists_update " +
                "BEFORE UPDATE OF task_id ON provider_task_links FOR EACH ROW WHEN NOT EXISTS " +
                "(SELECT 1 FROM tasks WHERE id = NEW.task_id) " +
                "BEGIN SELECT RAISE(ABORT, 'Provider task does not exist'); END"
        ]
    },
    {
        // Plane state IDs are scoped to a project. Rebuild the initial generic
        // cache so one workspace can map more than one remote project safely.
        version: 10,
        statements: [
            "DROP INDEX IF EXISTS provider_state_mappings_outbound_idx",
            "ALTER TABLE provider_state_mappings RENAME TO provider_state_mappings_v9",
            "CREATE TABLE provider_state_mappings (" +
                "workspace_id TEXT NOT NULL, provider TEXT NOT NULL, project_id TEXT NOT NULL, remote_state_id TEXT NOT NULL, " +
                "local_status TEXT NOT NULL, is_outbound INTEGER NOT NULL DEFAULT 0, remote_state_name TEXT NOT NULL DEFAULT '', " +
                "created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, " +
                "PRIMARY KEY (workspace_id, provider, project_id, remote_state_id), " +
                "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE CASCADE, " +
                "CHECK (local_status IN ('backlog', 'ready', 'in_progress', 'blocked', 'completed')), CHECK (is_outbound IN (0, 1)))",
            "CREATE UNIQUE INDEX provider_state_mappings_outbound_idx ON provider_state_mappings(workspace_id, provider, project_id, local_status) WHERE is_outbound = 1",
            "INSERT OR IGNORE INTO provider_state_mappings (workspace_id, provider, project_id, remote_state_id, local_status, is_outbound, remote_state_name, created_at_utc, updated_at_utc) " +
                "SELECT old.workspace_id, old.provider, projects.remote_project_id, old.remote_state_id, old.local_status, old.is_outbound, old.remote_state_name, old.created_at_utc, old.updated_at_utc " +
                "FROM provider_state_mappings_v9 AS old JOIN provider_project_mappings AS projects " +
                "ON projects.workspace_id = old.workspace_id AND projects.provider = old.provider",
            "DROP TABLE provider_state_mappings_v9"
        ]
    },
    {
        // Legacy Plane imports displayed identity metadata in editable task
        // fields. Move only the exact generated representation out of the
        // local title/description; provider_task_links retains that metadata.
        version: 11,
        statements: [
            "UPDATE tasks SET title = substr(title, length((SELECT remote_key FROM external_tasks WHERE task_id = tasks.id)) + 4) " +
                "WHERE EXISTS (SELECT 1 FROM external_tasks WHERE task_id = tasks.id AND provider = 'plane' " +
                "AND tasks.title LIKE '[' || external_tasks.remote_key || '] %')",
            "UPDATE tasks SET details = substr(details, 1, instr(details, char(10) || char(10) || 'Plane project:') - 1) " +
                "WHERE EXISTS (SELECT 1 FROM external_tasks WHERE task_id = tasks.id AND provider = 'plane' " +
                "AND instr(tasks.details, char(10) || char(10) || 'Plane project:') > 0 " +
                "AND tasks.details LIKE '%' || external_tasks.remote_url)"
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
        throw new Error("The database was created by a newer version of Workbench.")
    }

    for (let index = 0; index < migrations.length; index += 1) {
        const migration = migrations[index]
        if (migration.version <= currentVersion) {
            continue
        }
        for (let statementIndex = 0; statementIndex < migration.statements.length; statementIndex += 1) {
            const statement = migration.statements[statementIndex]
            const parameters = migration.version === 8 && statement.indexOf("SELECT 'workspace-") !== -1
                ? [appliedAtUtc, appliedAtUtc] : []
            tx.executeSql(statement, parameters)
        }
        tx.executeSql(
            "INSERT INTO schema_migrations (version, applied_at_utc) VALUES (?, ?)",
            [migration.version, appliedAtUtc]
        )
    }
}
