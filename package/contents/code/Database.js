.pragma library

.import QtQuick.LocalStorage as Sql
.import "Migrations.js" as Migrations

// Keep this established LocalStorage name so rebranding does not orphan user data.
const DATABASE_ID = "io.github.ownisticapps.worktodo"
const POSITION_GAP = 1024
const POSITION_OFFSET = 1000000000
const TRASH_RETENTION_DAYS = 30
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000
const TASK_PRIORITIES = ["none", "urgent", "high", "medium", "low"]

let databaseName = DATABASE_ID
let database
let initialized = false
let timezoneValidator = null

function nowUtc() {
    return new Date().toISOString()
}

function newId() {
    const timestamp = Date.now().toString(36)
    const random = Math.random().toString(36).slice(2, 12)
    return timestamp + "-" + random
}

function fail(message) {
    throw new Error(message)
}

function requireId(value, fieldName) {
    if (typeof value !== "string" || value.length === 0) {
        fail(fieldName + " is required.")
    }
    return value
}

function normalizedText(value, fieldName, maximumLength) {
    if (typeof value !== "string") {
        fail(fieldName + " must be text.")
    }
    const normalized = value.trim()
    if (codePointLength(normalized) === 0 || codePointLength(normalized) > maximumLength) {
        fail(fieldName + " must contain between 1 and " + maximumLength + " characters.")
    }
    return normalized
}

function codePointLength(value) {
    let count = 0
    for (let index = 0; index < value.length; index += 1) {
        const codeUnit = value.charCodeAt(index)
        if (codeUnit >= 0xd800 && codeUnit <= 0xdbff && index + 1 < value.length) {
            const nextCodeUnit = value.charCodeAt(index + 1)
            if (nextCodeUnit >= 0xdc00 && nextCodeUnit <= 0xdfff) {
                index += 1
            }
        }
        count += 1
    }
    return count
}

function requireUtcInstant(value, fieldName) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) {
        fail(fieldName + " must be a UTC ISO-8601 timestamp.")
    }
    const timestamp = new Date(value)
    if (isNaN(timestamp.getTime()) || timestamp.toISOString() !== value) {
        fail(fieldName + " must be a valid UTC ISO-8601 timestamp.")
    }
    return value
}

function requireTimezoneId(value) {
    const timezoneId = normalizedText(value, "Time zone", 100)
    if (!timezoneValidator || !timezoneValidator(timezoneId)) {
        fail("The time zone is invalid.")
    }
    return timezoneId
}

function requireStatusId(status) {
    return normalizedText(status, "Task status", 100)
}

function requireTaskPriority(priority) {
    if (TASK_PRIORITIES.indexOf(priority) === -1) {
        fail("Task priority must be none, urgent, high, medium, or low.")
    }
    return priority
}

function requireProvider(value) {
    return normalizedText(value, "Provider", 64)
}

function requireSyncState(value) {
    const states = ["in_sync", "pending_create", "pending_push", "conflict", "error"]
    if (states.indexOf(value) === -1) {
        fail("The provider sync state is invalid.")
    }
    return value
}

function jsonText(value, fieldName, fallback) {
    if (value === undefined) {
        return fallback
    }
    if (typeof value === "string") {
        try {
            JSON.parse(value)
        } catch (error) {
            fail(fieldName + " must be valid JSON.")
        }
        return value
    }
    try {
        const serialized = JSON.stringify(value)
        if (serialized === undefined) {
            fail(fieldName + " must be JSON-compatible.")
        }
        return serialized
    } catch (error) {
        fail(fieldName + " must be JSON-compatible.")
    }
}

function parsedJson(value, fallback) {
    try {
        return JSON.parse(value)
    } catch (error) {
        return fallback
    }
}

function nullableText(value, fieldName, maximumLength) {
    if (value === null) {
        return null
    }
    return normalizedText(value, fieldName, maximumLength)
}

function open() {
    if (!database) {
        database = Sql.LocalStorage.openDatabaseSync(
            databaseName,
            "1.0",
            "Workbench data",
            5 * 1024 * 1024
        )
    }
    return database
}

function rows(result) {
    const values = []
    for (let index = 0; index < result.rows.length; index += 1) {
        values.push(result.rows.item(index))
    }
    return values
}

function first(result) {
    return result.rows.length > 0 ? result.rows.item(0) : null
}

function write(operation) {
    initialize()
    let value
    open().transaction(function(tx) {
        value = operation(tx)
    })
    return value
}

function read(operation) {
    initialize()
    let value
    open().readTransaction(function(tx) {
        value = operation(tx)
    })
    return value
}

function initialize() {
    if (initialized) {
        return
    }
    open().transaction(function(tx) {
        // Qt LocalStorage permits PRAGMA calls only inside transactions, where SQLite
        // does not enable foreign keys. Migration triggers enforce the same references.
        tx.executeSql("PRAGMA foreign_keys = ON")
        Migrations.apply(tx, nowUtc())
        purgeExpiredTrashInTransaction(tx, nowUtc())
    })
    initialized = true
}

function configureDatabaseForTests(name) {
    if (typeof name !== "string" || name.length === 0) {
        fail("A test database name is required.")
    }
    databaseName = name
    database = null
    initialized = false
}

function setTimeZoneValidator(validator) {
    if (typeof validator !== "function") {
        fail("A time-zone validator function is required.")
    }
    timezoneValidator = validator
}

function currentDatabaseName() {
    return databaseName
}

function categoryById(tx, categoryId) {
    const category = first(tx.executeSql("SELECT * FROM categories WHERE id = ?", [categoryId]))
    if (!category) {
        fail("The category does not exist.")
    }
    return category
}

function activeCategoryById(tx, categoryId) {
    const category = categoryById(tx, categoryId)
    if (category.trashed_at_utc !== null) {
        fail("The category is in the trash.")
    }
    return category
}

function workflowStatusRecord(row) {
    return {
        id: row.id, name: row.name, isCompleted: row.is_completed === 1, position: row.position,
        workspaceId: row.workspace_id, createdAtUtc: row.created_at_utc, updatedAtUtc: row.updated_at_utc
    }
}

function workflowStatusById(tx, workspaceId, statusId) {
    const status = first(tx.executeSql(
        "SELECT * FROM workflow_statuses WHERE workspace_id = ? AND id = ?", [workspaceId, statusId]
    ))
    if (!status) {
        fail("The task status is not defined for this workbench.")
    }
    return status
}

function requireStatusForWorkspace(tx, workspaceId, statusId) {
    statusId = requireStatusId(statusId)
    workflowStatusById(tx, workspaceId, statusId)
    return statusId
}

function isCompletedStatusForTask(tx, taskId, statusId) {
    const row = first(tx.executeSql(
        "SELECT workflow_statuses.is_completed FROM tasks JOIN categories ON categories.id = tasks.category_id " +
        "JOIN workflow_statuses ON workflow_statuses.workspace_id = categories.workspace_id AND workflow_statuses.id = ? " +
        "WHERE tasks.id = ?", [statusId, taskId]
    ))
    if (!row) {
        fail("The task status is not defined for this workbench.")
    }
    return row.is_completed === 1
}

function assertTaskWorkflowStatusesForWorkspace(tx, taskId, workspaceId) {
    const invalid = first(tx.executeSql(
        "SELECT 1 FROM status_events WHERE task_id = ? AND (NOT EXISTS " +
        "(SELECT 1 FROM workflow_statuses WHERE workspace_id = ? AND id = status_events.status) " +
        "OR (previous_status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM workflow_statuses " +
        "WHERE workspace_id = ? AND id = status_events.previous_status))) LIMIT 1",
        [taskId, workspaceId, workspaceId]
    ))
    if (invalid) {
        fail("All task status history must be defined for the destination workbench.")
    }
}

function trashExpiryCutoff(currentUtc) {
    currentUtc = requireUtcInstant(currentUtc || nowUtc(), "Purge time")
    return new Date(new Date(currentUtc).getTime() - TRASH_RETENTION_DAYS * MILLISECONDS_PER_DAY).toISOString()
}

function purgeExpiredTrashInTransaction(tx, currentUtc) {
    const cutoffUtc = trashExpiryCutoff(currentUtc)
    const expiredCategories = tx.executeSql(
        "SELECT COUNT(*) AS count FROM categories WHERE trashed_at_utc IS NOT NULL AND trashed_at_utc <= ?",
        [cutoffUtc]
    )
    if (expiredCategories.rows.item(0).count === 0) {
        return 0
    }
    const categoryClause = "category_id IN (SELECT id FROM categories WHERE trashed_at_utc IS NOT NULL AND trashed_at_utc <= ?)"
    tx.executeSql("DELETE FROM provider_task_links WHERE task_id IN (SELECT id FROM tasks WHERE " + categoryClause + ")", [cutoffUtc])
    tx.executeSql("DELETE FROM external_tasks WHERE task_id IN (SELECT id FROM tasks WHERE " + categoryClause + ")", [cutoffUtc])
    tx.executeSql("DELETE FROM work_sessions WHERE task_id IN (SELECT id FROM tasks WHERE " + categoryClause + ")", [cutoffUtc])
    tx.executeSql("DELETE FROM status_events WHERE task_id IN (SELECT id FROM tasks WHERE " + categoryClause + ")", [cutoffUtc])
    tx.executeSql("DELETE FROM tasks WHERE " + categoryClause, [cutoffUtc])
    tx.executeSql("DELETE FROM categories WHERE trashed_at_utc IS NOT NULL AND trashed_at_utc <= ?", [cutoffUtc])
    return expiredCategories.rows.item(0).count
}

function taskById(tx, taskId) {
    const task = first(tx.executeSql("SELECT * FROM tasks WHERE id = ?", [taskId]))
    if (!task) {
        fail("The task does not exist.")
    }
    return task
}

function assertTaskMoveProviderCompatible(tx, task, targetCategoryId) {
    if (task.category_id === targetCategoryId) {
        return
    }
    const link = first(tx.executeSql("SELECT provider, project_id FROM provider_task_links WHERE task_id = ?", [task.id]))
        || first(tx.executeSql("SELECT provider, project_id FROM external_tasks WHERE task_id = ?", [task.id]))
    if (!link) {
        return
    }
    const sourceCategory = activeCategoryById(tx, task.category_id)
    const targetCategory = activeCategoryById(tx, targetCategoryId)
    if (sourceCategory.workspace_id !== targetCategory.workspace_id) {
        fail("A provider-linked task cannot move out of its workspace.")
    }
    const mapping = first(tx.executeSql(
        "SELECT remote_project_id FROM provider_project_mappings WHERE category_id = ? AND provider = ?",
        [targetCategoryId, link.provider]
    ))
    if (!mapping || mapping.remote_project_id !== link.project_id) {
        fail("A provider-linked task cannot move to a different remote project.")
    }
}

function activeSessions(tx) {
    return rows(tx.executeSql(
        "SELECT * FROM work_sessions WHERE ended_at_utc IS NULL ORDER BY started_at_utc, id"
    ))
}

function activeSession(tx) {
    const sessions = activeSessions(tx)
    return sessions.length > 0 ? sessions[0] : null
}

function nextStatusSequence(tx, taskId) {
    const result = tx.executeSql(
        "SELECT COALESCE(MAX(sequence), 0) + 1 AS sequence FROM status_events WHERE task_id = ?",
        [taskId]
    )
    return result.rows.item(0).sequence
}

function assertSessionCanEnd(tx, session, endedAtUtc) {
    requireUtcInstant(endedAtUtc, "End time")
    if (endedAtUtc < session.started_at_utc) {
        fail("The end time cannot be before the start time.")
    }
    if (hasManualSessionOverlap(tx, session.started_at_utc, endedAtUtc, session.id)) {
        fail("The work session would overlap another session.")
    }
}

function closeSession(tx, session, endedAtUtc) {
    assertSessionCanEnd(tx, session, endedAtUtc)
    tx.executeSql(
        "UPDATE work_sessions SET ended_at_utc = ?, updated_at_utc = ? WHERE id = ?",
        [endedAtUtc, endedAtUtc, session.id]
    )
    recalculateTrackedSeconds(tx, session.task_id)
    session.ended_at_utc = endedAtUtc
    return session
}

function recalculateTrackedSeconds(tx, taskId) {
    tx.executeSql(
        "UPDATE tasks SET tracked_seconds = COALESCE((SELECT SUM(strftime('%s', ended_at_utc) - strftime('%s', started_at_utc)) FROM work_sessions WHERE task_id = ? AND ended_at_utc IS NOT NULL), 0) WHERE id = ?",
        [taskId, taskId]
    )
}

function closeActiveSessionForTask(tx, taskId, endedAtUtc) {
    const session = first(tx.executeSql(
        "SELECT * FROM work_sessions WHERE task_id = ? AND ended_at_utc IS NULL",
        [taskId]
    ))
    return session ? closeSession(tx, session, endedAtUtc) : null
}

function stopTimersExceptInTransaction(tx, taskId, stoppedAtUtc) {
    const active = activeSessions(tx)
    const stopped = []
    for (let index = 0; index < active.length; index += 1) {
        if (active[index].task_id !== taskId) {
            stopped.push(closeSession(tx, active[index], stoppedAtUtc))
        }
    }
    return stopped
}

function nextPosition(tx, tableName, whereClause, parameters) {
    const result = tx.executeSql(
        "SELECT COALESCE(MAX(position), 0) AS position FROM " + tableName + " " + whereClause,
        parameters
    )
    return result.rows.item(0).position + POSITION_GAP
}

function rebalanceTasks(tx, categoryId, excludedTaskId) {
    tx.executeSql(
        "UPDATE tasks SET position = position + ? WHERE category_id = ?",
        [POSITION_OFFSET, categoryId]
    )
    const ordered = rows(tx.executeSql(
        "SELECT id FROM tasks WHERE category_id = ? ORDER BY position, created_at_utc, id",
        [categoryId]
    ))
    for (let index = 0; index < ordered.length; index += 1) {
        tx.executeSql("UPDATE tasks SET position = ? WHERE id = ?", [(index + 1) * POSITION_GAP, ordered[index].id])
    }
}

function positionForMove(tx, categoryId, taskId, targetTaskId, placement) {
    const ordered = rows(tx.executeSql(
        "SELECT id, position FROM tasks WHERE category_id = ? AND id <> ? ORDER BY position, created_at_utc, id",
        [categoryId, taskId]
    ))
    let insertionIndex = ordered.length
    if (targetTaskId) {
        for (let index = 0; index < ordered.length; index += 1) {
            if (ordered[index].id === targetTaskId) {
                insertionIndex = placement === "after" ? index + 1 : index
                break
            }
        }
        if (insertionIndex === ordered.length && ordered.length > 0
            && ordered[ordered.length - 1].id !== targetTaskId) {
            fail("The destination task does not exist in the destination category.")
        }
    }

    let previous = insertionIndex > 0 ? ordered[insertionIndex - 1].position : null
    let next = insertionIndex < ordered.length ? ordered[insertionIndex].position : null
    if ((previous !== null && next !== null && next - previous < 2)
        || (previous === null && next !== null && next < 2)) {
        rebalanceTasks(tx, categoryId)
        return positionForMove(tx, categoryId, taskId, targetTaskId, placement)
    }
    if (previous === null && next === null) {
        return POSITION_GAP
    }
    if (previous === null) {
        return Math.floor(next / 2)
    }
    if (next === null) {
        return previous + POSITION_GAP
    }
    return previous + Math.floor((next - previous) / 2)
}

function reconcileStatusHistory(tx, taskId) {
    const events = rows(tx.executeSql(
        "SELECT id, status, occurred_at_utc FROM status_events WHERE task_id = ? " +
        "ORDER BY occurred_at_utc, sequence, id",
        [taskId]
    ))
    if (events.length === 0) {
        fail("A task must retain at least one status event.")
    }
    let previousStatus = null
    for (let index = 0; index < events.length; index += 1) {
        tx.executeSql("UPDATE status_events SET previous_status = ? WHERE id = ?", [previousStatus, events[index].id])
        previousStatus = events[index].status
    }
    const current = events[events.length - 1]
    tx.executeSql(
        "UPDATE tasks SET status = ?, completed_at_utc = ?, updated_at_utc = ? WHERE id = ?",
        [previousStatus, isCompletedStatusForTask(tx, taskId, previousStatus) ? current.occurred_at_utc : null, nowUtc(), taskId]
    )
    return { status: previousStatus, occurredAtUtc: current.occurred_at_utc }
}

function positionForCategoryMove(tx, workspaceId, categoryId, targetCategoryId, placement) {
    const ordered = rows(tx.executeSql(
        "SELECT id, position FROM categories WHERE workspace_id = ? AND trashed_at_utc IS NULL AND id <> ? " +
        "ORDER BY position, created_at_utc, id",
        [workspaceId, categoryId]
    ))
    let index = ordered.length
    if (targetCategoryId) {
        index = ordered.findIndex(function(category) { return category.id === targetCategoryId })
        if (index < 0) {
            fail("The destination category does not exist.")
        }
        if (placement === "after") {
            index += 1
        }
    }
    let previous = index > 0 ? ordered[index - 1].position : null
    let next = index < ordered.length ? ordered[index].position : null
    if ((previous !== null && next !== null && next - previous < 2)
        || (previous === null && next !== null && next < 2)) {
        tx.executeSql(
            "UPDATE categories SET position = position + ? WHERE workspace_id = ? AND trashed_at_utc IS NULL",
            [POSITION_OFFSET, workspaceId]
        )
        const categories = rows(tx.executeSql(
            "SELECT id FROM categories WHERE workspace_id = ? AND trashed_at_utc IS NULL " +
            "ORDER BY position, created_at_utc, id",
            [workspaceId]
        ))
        for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex += 1) {
            tx.executeSql("UPDATE categories SET position = ? WHERE id = ?", [(categoryIndex + 1) * POSITION_GAP, categories[categoryIndex].id])
        }
        return positionForCategoryMove(tx, workspaceId, categoryId, targetCategoryId, placement)
    }
    if (previous === null && next === null) {
        return POSITION_GAP
    }
    if (previous === null) {
        return Math.floor(next / 2)
    }
    if (next === null) {
        return previous + POSITION_GAP
    }
    return previous + Math.floor((next - previous) / 2)
}

function workspaceById(tx, workspaceId) {
    const workspace = first(tx.executeSql("SELECT * FROM workspaces WHERE id = ?", [workspaceId]))
    if (!workspace) {
        fail("The workspace does not exist.")
    }
    return workspace
}

function defaultWorkspace(tx) {
    const workspace = first(tx.executeSql("SELECT * FROM workspaces ORDER BY position, created_at_utc, id LIMIT 1"))
    if (!workspace) {
        fail("At least one workspace is required.")
    }
    return workspace
}

function listWorkspaces() {
    return read(function(tx) {
        return rows(tx.executeSql("SELECT * FROM workspaces ORDER BY position, created_at_utc, id"))
    })
}

function createWorkspace(input) {
    input = input || {}
    const name = normalizedText(input.name, "Workspace name", 100)
    return write(function(tx) {
        const timestamp = nowUtc()
        const workspace = {
            id: newId(), name: name,
            position: nextPosition(tx, "workspaces", "", []),
            created_at_utc: timestamp, updated_at_utc: timestamp
        }
        tx.executeSql(
            "INSERT INTO workspaces (id, name, position, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?)",
            [workspace.id, workspace.name, workspace.position, workspace.created_at_utc, workspace.updated_at_utc]
        )
        const defaults = [
            ["backlog", "Backlog", 0], ["ready", "Ready", 0], ["in_progress", "In progress", 0],
            ["blocked", "Blocked", 0], ["completed", "Completed", 1]
        ]
        for (let index = 0; index < defaults.length; index += 1) {
            tx.executeSql(
                "INSERT INTO workflow_statuses (workspace_id, id, name, is_completed, position, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [workspace.id, defaults[index][0], defaults[index][1], defaults[index][2], (index + 1) * POSITION_GAP, timestamp, timestamp]
            )
        }
        return workspace
    })
}

function listWorkflowStatuses(workspaceId) {
    workspaceId = requireId(workspaceId, "Workspace ID")
    return read(function(tx) {
        workspaceById(tx, workspaceId)
        return rows(tx.executeSql(
            "SELECT * FROM workflow_statuses WHERE workspace_id = ? ORDER BY position, name, id", [workspaceId]
        )).map(workflowStatusRecord)
    })
}

function createWorkflowStatus(input) {
    input = input || {}
    const workspaceId = requireId(input.workspaceId, "Workspace ID")
    const name = normalizedText(input.name, "Status name", 100)
    const isCompleted = input.isCompleted === true ? 1 : 0
    return write(function(tx) {
        workspaceById(tx, workspaceId)
        const timestamp = nowUtc()
        const status = {
            id: newId(), workspaceId: workspaceId, name: name, isCompleted: isCompleted,
            position: nextPosition(tx, "workflow_statuses", "WHERE workspace_id = ?", [workspaceId]),
            createdAtUtc: timestamp, updatedAtUtc: timestamp
        }
        tx.executeSql(
            "INSERT INTO workflow_statuses (workspace_id, id, name, is_completed, position, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [status.workspaceId, status.id, status.name, status.isCompleted, status.position, status.createdAtUtc, status.updatedAtUtc]
        )
        return workflowStatusRecord(first(tx.executeSql(
            "SELECT * FROM workflow_statuses WHERE workspace_id = ? AND id = ?", [workspaceId, status.id]
        )))
    })
}

function workspaceProviderRecord(row) {
    if (!row) {
        return null
    }
    return {
        workspaceId: row.workspace_id,
        provider: row.provider,
        connectionId: row.connection_id,
        config: parsedJson(row.config_json, {}),
        configJson: row.config_json,
        createdAtUtc: row.created_at_utc,
        updatedAtUtc: row.updated_at_utc
    }
}

function getWorkspaceProvider(workspaceId) {
    workspaceId = requireId(workspaceId, "Workspace ID")
    return read(function(tx) {
        workspaceById(tx, workspaceId)
        return workspaceProviderRecord(first(tx.executeSql(
            "SELECT * FROM workspace_providers WHERE workspace_id = ?", [workspaceId]
        )))
    })
}

// Pass provider: null to remove the optional integration and retain all local data.
function setWorkspaceProvider(input) {
    input = input || {}
    const workspaceId = requireId(input.workspaceId, "Workspace ID")
    if (input.provider === null) {
        return write(function(tx) {
            workspaceById(tx, workspaceId)
            tx.executeSql("DELETE FROM workspace_providers WHERE workspace_id = ?", [workspaceId])
            return null
        })
    }
    const provider = requireProvider(input.provider)
    const connectionId = input.connectionId === undefined || input.connectionId === null
        ? null : normalizedText(input.connectionId, "Connection ID", 200)
    const configJson = jsonText(input.config !== undefined ? input.config : input.configJson, "Provider configuration", "{}")
    return write(function(tx) {
        workspaceById(tx, workspaceId)
        const timestamp = nowUtc()
        tx.executeSql(
            "INSERT INTO workspace_providers (workspace_id, provider, connection_id, config_json, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(workspace_id) DO UPDATE SET provider = excluded.provider, " +
            "connection_id = excluded.connection_id, config_json = excluded.config_json, updated_at_utc = excluded.updated_at_utc",
            [workspaceId, provider, connectionId, configJson, timestamp, timestamp]
        )
        return workspaceProviderRecord(first(tx.executeSql("SELECT * FROM workspace_providers WHERE workspace_id = ?", [workspaceId])))
    })
}

function providerProjectMappingRecord(row) {
    return {
        categoryId: row.category_id, workspaceId: row.workspace_id, provider: row.provider,
        remoteProjectId: row.remote_project_id, remoteProjectName: row.remote_project_name,
        createdAtUtc: row.created_at_utc, updatedAtUtc: row.updated_at_utc
    }
}

function listProviderProjectMappings(workspaceId) {
    workspaceId = requireId(workspaceId, "Workspace ID")
    return read(function(tx) {
        workspaceById(tx, workspaceId)
        return rows(tx.executeSql(
            "SELECT * FROM provider_project_mappings WHERE workspace_id = ? ORDER BY remote_project_name, remote_project_id",
            [workspaceId]
        )).map(providerProjectMappingRecord)
    })
}

function saveProviderProjectMapping(input) {
    input = input || {}
    const workspaceId = requireId(input.workspaceId, "Workspace ID")
    const categoryId = requireId(input.categoryId, "Category ID")
    const provider = requireProvider(input.provider)
    const remoteProjectId = normalizedText(input.remoteProjectId, "Remote project ID", 200)
    const remoteProjectName = input.remoteProjectName === undefined ? "" : String(input.remoteProjectName)
    return write(function(tx) {
        const category = activeCategoryById(tx, categoryId)
        workspaceById(tx, workspaceId)
        if (category.workspace_id !== workspaceId) {
            fail("The category does not belong to the workspace.")
        }
        const binding = first(tx.executeSql("SELECT provider FROM workspace_providers WHERE workspace_id = ?", [workspaceId]))
        if (!binding || binding.provider !== provider) {
            fail("The workspace is not connected to this provider.")
        }
        const timestamp = nowUtc()
        tx.executeSql(
            "INSERT INTO provider_project_mappings (category_id, workspace_id, provider, remote_project_id, remote_project_name, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(category_id) DO UPDATE SET workspace_id = excluded.workspace_id, " +
            "provider = excluded.provider, remote_project_id = excluded.remote_project_id, remote_project_name = excluded.remote_project_name, updated_at_utc = excluded.updated_at_utc",
            [categoryId, workspaceId, provider, remoteProjectId, remoteProjectName, timestamp, timestamp]
        )
        return providerProjectMappingRecord(first(tx.executeSql("SELECT * FROM provider_project_mappings WHERE category_id = ?", [categoryId])))
    })
}

function removeProviderProjectMapping(categoryId) {
    categoryId = requireId(categoryId, "Category ID")
    return write(function(tx) { tx.executeSql("DELETE FROM provider_project_mappings WHERE category_id = ?", [categoryId]) })
}

function providerStateMappingRecord(row) {
    return { workspaceId: row.workspace_id, provider: row.provider, projectId: row.project_id, remoteStateId: row.remote_state_id,
        remoteStateName: row.remote_state_name, localStatus: row.local_status, isOutbound: row.is_outbound === 1,
        createdAtUtc: row.created_at_utc, updatedAtUtc: row.updated_at_utc }
}

function listProviderStateMappings(workspaceId, provider, projectId) {
    workspaceId = requireId(workspaceId, "Workspace ID")
    provider = requireProvider(provider)
    projectId = requireId(projectId, "Project ID")
    return read(function(tx) {
        return rows(tx.executeSql("SELECT * FROM provider_state_mappings WHERE workspace_id = ? AND provider = ? AND project_id = ? ORDER BY remote_state_name, remote_state_id", [workspaceId, provider, projectId])).map(providerStateMappingRecord)
    })
}

function saveProviderStateMapping(input) {
    input = input || {}
    const workspaceId = requireId(input.workspaceId, "Workspace ID")
    const provider = requireProvider(input.provider)
    const projectId = requireId(input.projectId, "Project ID")
    const remoteStateId = normalizedText(input.remoteStateId, "Remote state ID", 200)
    const localStatus = requireStatusId(input.localStatus)
    const isOutbound = input.isOutbound === true ? 1 : 0
    const remoteStateName = input.remoteStateName === undefined ? "" : String(input.remoteStateName)
    return write(function(tx) {
        workspaceById(tx, workspaceId)
        requireStatusForWorkspace(tx, workspaceId, localStatus)
        const timestamp = nowUtc()
        if (isOutbound) {
            tx.executeSql("UPDATE provider_state_mappings SET is_outbound = 0, updated_at_utc = ? WHERE workspace_id = ? AND provider = ? AND project_id = ? AND local_status = ?", [timestamp, workspaceId, provider, projectId, localStatus])
        }
        tx.executeSql("INSERT INTO provider_state_mappings (workspace_id, provider, project_id, remote_state_id, local_status, is_outbound, remote_state_name, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(workspace_id, provider, project_id, remote_state_id) DO UPDATE SET local_status = excluded.local_status, is_outbound = excluded.is_outbound, remote_state_name = excluded.remote_state_name, updated_at_utc = excluded.updated_at_utc", [workspaceId, provider, projectId, remoteStateId, localStatus, isOutbound, remoteStateName, timestamp, timestamp])
        return providerStateMappingRecord(first(tx.executeSql("SELECT * FROM provider_state_mappings WHERE workspace_id = ? AND provider = ? AND project_id = ? AND remote_state_id = ?", [workspaceId, provider, projectId, remoteStateId])))
    })
}

function listProviderMembers(workspaceId, provider, projectId) {
    workspaceId = requireId(workspaceId, "Workspace ID")
    provider = requireProvider(provider)
    projectId = requireId(projectId, "Project ID")
    return read(function(tx) {
        return rows(tx.executeSql("SELECT workspace_id AS workspaceId, provider, project_id AS projectId, member_id AS memberId, member_name AS memberName, member_email AS memberEmail, member_payload_json AS memberPayloadJson, updated_at_utc AS updatedAtUtc FROM provider_members WHERE workspace_id = ? AND provider = ? AND project_id = ? ORDER BY member_name, member_id", [workspaceId, provider, projectId]))
    })
}

function replaceProviderMembers(input) {
    input = input || {}
    const workspaceId = requireId(input.workspaceId, "Workspace ID")
    const provider = requireProvider(input.provider)
    const projectId = requireId(input.projectId, "Project ID")
    const members = input.members || []
    if (!Array.isArray(members)) {
        fail("Provider members must be an array.")
    }
    return write(function(tx) {
        workspaceById(tx, workspaceId)
        const timestamp = nowUtc()
        tx.executeSql("DELETE FROM provider_members WHERE workspace_id = ? AND provider = ? AND project_id = ?", [workspaceId, provider, projectId])
        for (let index = 0; index < members.length; index += 1) {
            const member = members[index] || {}
            tx.executeSql("INSERT INTO provider_members (workspace_id, provider, project_id, member_id, member_name, member_email, member_payload_json, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [workspaceId, provider, projectId, requireId(member.memberId, "Member ID"), member.memberName || "", member.memberEmail || "", jsonText(member.memberPayload !== undefined ? member.memberPayload : member.memberPayloadJson, "Member payload", "{}"), timestamp])
        }
        return listProviderMembersInTransaction(tx, workspaceId, provider, projectId)
    })
}

function listProviderMembersInTransaction(tx, workspaceId, provider, projectId) {
    return rows(tx.executeSql("SELECT workspace_id AS workspaceId, provider, project_id AS projectId, member_id AS memberId, member_name AS memberName, member_email AS memberEmail, member_payload_json AS memberPayloadJson, updated_at_utc AS updatedAtUtc FROM provider_members WHERE workspace_id = ? AND provider = ? AND project_id = ? ORDER BY member_name, member_id", [workspaceId, provider, projectId]))
}

function listCategories(workspaceId) {
    purgeExpiredTrash()
    return read(function(tx) {
        if (workspaceId) {
            workspaceById(tx, workspaceId)
            return rows(tx.executeSql(
                "SELECT * FROM categories WHERE workspace_id = ? AND trashed_at_utc IS NULL " +
                "ORDER BY position, created_at_utc, id",
                [workspaceId]
            ))
        }
        return rows(tx.executeSql(
            "SELECT * FROM categories WHERE trashed_at_utc IS NULL ORDER BY workspace_id, position, created_at_utc, id"
        ))
    })
}

function categoryTimeTotal(categoryId, currentUtc) {
    categoryId = requireId(categoryId, "Category ID")
    const activeEndUtc = requireUtcInstant(currentUtc || nowUtc(), "Category time end")
    purgeExpiredTrash()
    return read(function(tx) {
        activeCategoryById(tx, categoryId)
        const total = { categoryId: categoryId, trackedSeconds: 0, activeStartedAts: [],
            intervalStartUtc: "", intervalEndUtc: "" }
        const sessions = rows(tx.executeSql(
            "SELECT work_sessions.started_at_utc AS startedAtUtc, " +
            "MIN(COALESCE(work_sessions.ended_at_utc, ?), ?) AS endedAtUtc, work_sessions.ended_at_utc IS NULL AS active " +
            "FROM work_sessions JOIN tasks ON tasks.id = work_sessions.task_id " +
            "WHERE tasks.category_id = ? AND work_sessions.started_at_utc < ? " +
            "ORDER BY work_sessions.started_at_utc, work_sessions.id",
            [activeEndUtc, activeEndUtc, categoryId, activeEndUtc]
        ))
        for (let index = 0; index < sessions.length; index += 1) {
            const session = sessions[index]
            if (session.active) {
                total.activeStartedAts.push(session.startedAtUtc)
            }
            if (!total.intervalStartUtc) {
                total.intervalStartUtc = session.startedAtUtc
                total.intervalEndUtc = session.endedAtUtc
            } else if (session.startedAtUtc <= total.intervalEndUtc) {
                if (session.endedAtUtc > total.intervalEndUtc) {
                    total.intervalEndUtc = session.endedAtUtc
                }
            } else {
                total.trackedSeconds += (Date.parse(total.intervalEndUtc) - Date.parse(total.intervalStartUtc)) / 1000
                total.intervalStartUtc = session.startedAtUtc
                total.intervalEndUtc = session.endedAtUtc
            }
        }
        if (total.intervalStartUtc) {
            total.trackedSeconds += (Date.parse(total.intervalEndUtc) - Date.parse(total.intervalStartUtc)) / 1000
        }
        delete total.intervalStartUtc
        delete total.intervalEndUtc
        return total
    })
}

function listActiveCategorySessions() {
    purgeExpiredTrash()
    return read(function(tx) {
        return rows(tx.executeSql(
            "SELECT tasks.category_id AS categoryId, work_sessions.started_at_utc AS startedAtUtc " +
            "FROM work_sessions JOIN tasks ON tasks.id = work_sessions.task_id " +
            "JOIN categories ON categories.id = tasks.category_id " +
            "WHERE categories.trashed_at_utc IS NULL AND work_sessions.ended_at_utc IS NULL"
        ))
    })
}

function listTrashedCategories(workspaceId) {
    purgeExpiredTrash()
    return read(function(tx) {
        if (workspaceId) {
            workspaceById(tx, workspaceId)
            return rows(tx.executeSql(
                "SELECT * FROM categories WHERE workspace_id = ? AND trashed_at_utc IS NOT NULL " +
                "ORDER BY trashed_at_utc DESC, position, id",
                [workspaceId]
            ))
        }
        return rows(tx.executeSql(
            "SELECT * FROM categories WHERE trashed_at_utc IS NOT NULL ORDER BY trashed_at_utc DESC, position, id"
        ))
    })
}

function createCategory(input) {
    input = input || {}
    const name = normalizedText(input.name, "Category name", 100)
    const color = normalizedText(input.color || "#3daee9", "Category color", 32)
    return write(function(tx) {
        const workspace = input.workspaceId ? workspaceById(tx, requireId(input.workspaceId, "Workspace ID")) : defaultWorkspace(tx)
        const timestamp = nowUtc()
        const category = {
            id: newId(),
            workspace_id: workspace.id,
            name: name,
            color: color,
            position: nextPosition(tx, "categories", "WHERE workspace_id = ? AND trashed_at_utc IS NULL", [workspace.id]),
            collapsed: input.collapsed ? 1 : 0,
            created_at_utc: timestamp,
            updated_at_utc: timestamp
        }
        tx.executeSql(
            "INSERT INTO categories (id, workspace_id, name, color, position, collapsed, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [category.id, category.workspace_id, category.name, category.color, category.position,
             category.collapsed, category.created_at_utc, category.updated_at_utc]
        )
        return category
    })
}

function updateCategory(input) {
    input = input || {}
    const categoryId = requireId(input.id, "Category ID")
    return write(function(tx) {
        const current = activeCategoryById(tx, categoryId)
        const name = input.name === undefined ? current.name : normalizedText(input.name, "Category name", 100)
        const color = input.color === undefined ? current.color : normalizedText(input.color, "Category color", 32)
        const collapsed = input.collapsed === undefined ? current.collapsed : (input.collapsed ? 1 : 0)
        const workspace = input.workspaceId === undefined
            ? workspaceById(tx, current.workspace_id)
            : workspaceById(tx, requireId(input.workspaceId, "Workspace ID"))
        if (workspace.id !== current.workspace_id && first(tx.executeSql(
            "SELECT 1 FROM provider_project_mappings WHERE category_id = ?", [categoryId]
        ))) {
            fail("A provider-mapped category cannot move to a different workspace.")
        }
        if (workspace.id !== current.workspace_id) {
            const invalid = first(tx.executeSql(
                "SELECT 1 FROM status_events JOIN tasks ON tasks.id = status_events.task_id WHERE tasks.category_id = ? AND " +
                "(NOT EXISTS (SELECT 1 FROM workflow_statuses WHERE workspace_id = ? AND id = status_events.status) " +
                "OR (status_events.previous_status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM workflow_statuses " +
                "WHERE workspace_id = ? AND id = status_events.previous_status))) LIMIT 1",
                [categoryId, workspace.id, workspace.id]
            ))
            if (invalid) {
                fail("All task status history must be defined for the destination workbench.")
            }
        }
        const position = workspace.id === current.workspace_id ? current.position
            : nextPosition(tx, "categories", "WHERE workspace_id = ? AND trashed_at_utc IS NULL", [workspace.id])
        const timestamp = nowUtc()
        tx.executeSql(
            "UPDATE categories SET workspace_id = ?, name = ?, color = ?, collapsed = ?, position = ?, " +
            "updated_at_utc = ? WHERE id = ?",
            [workspace.id, name, color, collapsed, position, timestamp, categoryId]
        )
        return { id: categoryId, workspaceId: workspace.id, name: name, color: color,
            collapsed: collapsed, position: position }
    })
}

function moveCategory(input) {
    input = input || {}
    const categoryId = requireId(input.categoryId, "Category ID")
    const targetCategoryId = input.targetCategoryId || null
    const placement = input.placement === "after" ? "after" : "before"
    return write(function(tx) {
        activeCategoryById(tx, categoryId)
        if (targetCategoryId) {
            activeCategoryById(tx, targetCategoryId)
        }
        const category = activeCategoryById(tx, categoryId)
        if (targetCategoryId && categoryById(tx, targetCategoryId).workspace_id !== category.workspace_id) {
            fail("Categories can only be reordered within the same workspace.")
        }
        const position = positionForCategoryMove(tx, category.workspace_id, categoryId, targetCategoryId, placement)
        tx.executeSql("UPDATE categories SET position = ?, updated_at_utc = ? WHERE id = ?", [position, nowUtc(), categoryId])
        return position
    })
}

function deleteCategory(categoryId) {
    categoryId = requireId(categoryId, "Category ID")
    return write(function(tx) {
        activeCategoryById(tx, categoryId)
        const timestamp = nowUtc()
        tx.executeSql(
            "UPDATE work_sessions SET ended_at_utc = CASE WHEN started_at_utc > ? THEN started_at_utc ELSE ? END, updated_at_utc = ? " +
            "WHERE ended_at_utc IS NULL AND task_id IN (SELECT id FROM tasks WHERE category_id = ?)",
            [timestamp, timestamp, timestamp, categoryId]
        )
        tx.executeSql(
            "UPDATE tasks SET tracked_seconds = COALESCE((SELECT SUM(strftime('%s', ended_at_utc) - strftime('%s', started_at_utc)) FROM work_sessions WHERE task_id = tasks.id AND ended_at_utc IS NOT NULL), 0) WHERE category_id = ?",
            [categoryId]
        )
        tx.executeSql(
            "UPDATE categories SET trashed_at_utc = ?, updated_at_utc = ? WHERE id = ?",
            [timestamp, timestamp, categoryId]
        )
    })
}

function restoreCategory(categoryId) {
    categoryId = requireId(categoryId, "Category ID")
    return write(function(tx) {
        const category = categoryById(tx, categoryId)
        if (category.trashed_at_utc === null) {
            return category
        }
        const timestamp = nowUtc()
        const position = nextPosition(tx, "categories", "WHERE workspace_id = ? AND trashed_at_utc IS NULL", [category.workspace_id])
        tx.executeSql(
            "UPDATE categories SET trashed_at_utc = NULL, position = ?, updated_at_utc = ? WHERE id = ?",
            [position, timestamp, categoryId]
        )
        category.trashed_at_utc = null
        category.position = position
        category.updated_at_utc = timestamp
        return category
    })
}

function purgeExpiredTrash(currentUtc) {
    return write(function(tx) {
        return purgeExpiredTrashInTransaction(tx, currentUtc || nowUtc())
    })
}

function listTasks(filter) {
    filter = filter || {}
    purgeExpiredTrash()
    const statuses = filter.statuses || []
    const showArchived = filter.showArchived === true
    const workspaceId = filter.workspaceId || ""
    for (let index = 0; index < statuses.length; index += 1) {
        requireStatusId(statuses[index])
    }
    return read(function(tx) {
        const clauses = ["categories.trashed_at_utc IS NULL", showArchived ? "1 = 1" : "tasks.archived_at_utc IS NULL"]
        const parameters = []
        if (workspaceId) {
            workspaceById(tx, workspaceId)
            clauses.push("categories.workspace_id = ?")
            parameters.push(workspaceId)
            for (let index = 0; index < statuses.length; index += 1) {
                requireStatusForWorkspace(tx, workspaceId, statuses[index])
            }
        }
        if (statuses.length > 0) {
            clauses.push("tasks.status IN (" + statuses.map(function() { return "?" }).join(", ") + ")")
            for (let index = 0; index < statuses.length; index += 1) {
                parameters.push(statuses[index])
            }
        }
        return rows(tx.executeSql(
            "SELECT tasks.id AS taskId, tasks.category_id AS categoryId, categories.workspace_id AS workspaceId, " +
            "categories.name AS categoryName, " +
            "categories.color AS categoryColor, categories.collapsed AS categoryCollapsed, workflow_statuses.name AS statusName, tasks.title, tasks.details, " +
            "tasks.status, tasks.priority, tasks.position, tasks.archived_at_utc AS archivedAtUtc, " +
            "tasks.tracked_seconds AS trackedSeconds, " +
            "active_session.started_at_utc AS activeStartedAt " +
            "FROM tasks JOIN categories ON categories.id = tasks.category_id " +
            "LEFT JOIN workflow_statuses ON workflow_statuses.workspace_id = categories.workspace_id AND workflow_statuses.id = tasks.status " +
            "LEFT JOIN work_sessions AS active_session ON active_session.task_id = tasks.id AND active_session.ended_at_utc IS NULL " +
            "WHERE " + clauses.join(" AND ") +
            " ORDER BY categories.position, tasks.position, tasks.created_at_utc, tasks.id",
            parameters
        ))
    })
}

function getTask(taskId) {
    taskId = requireId(taskId, "Task ID")
    return read(function(tx) {
        const task = first(tx.executeSql(
            "SELECT tasks.*, categories.name AS category_name, categories.color AS category_color, workflow_statuses.name AS statusName, " +
            "tasks.tracked_seconds AS trackedSeconds, " +
            "(SELECT started_at_utc FROM work_sessions WHERE task_id = tasks.id AND ended_at_utc IS NULL) AS activeStartedAt " +
            "FROM tasks JOIN categories ON categories.id = tasks.category_id " +
            "LEFT JOIN workflow_statuses ON workflow_statuses.workspace_id = categories.workspace_id AND workflow_statuses.id = tasks.status " +
            "WHERE tasks.id = ?",
            [taskId]
        ))
        if (!task) {
            return null
        }
        task.workSessions = listWorkSessionsInTransaction(tx, taskId)
        task.statusEvents = listStatusEventsInTransaction(tx, taskId)
        return task
    })
}

function taskExternalLinkRecord(row) {
    if (!row) {
        return null
    }
    return {
        taskId: row.task_id, provider: row.provider, remoteId: row.remote_id, remoteKey: row.remote_key,
        remoteUrl: row.remote_url, projectId: row.project_id, remoteUpdatedAt: row.remote_updated_at,
        remoteRevision: row.remote_revision, lastLocalUpdatedAt: row.last_local_updated_at,
        lastSyncedAt: row.last_synced_at, syncState: row.sync_state, syncError: row.sync_error,
        assigneeIds: parsedJson(row.assignee_ids_json, []), assigneeIdsJson: row.assignee_ids_json,
        managedBaseline: parsedJson(row.managed_baseline_json, {}), managedBaselineJson: row.managed_baseline_json,
        remotePayload: parsedJson(row.remote_payload_json, {}), remotePayloadJson: row.remote_payload_json,
        createdAtUtc: row.created_at_utc, updatedAtUtc: row.updated_at_utc
    }
}

function getTaskExternalLink(taskId) {
    taskId = requireId(taskId, "Task ID")
    return read(function(tx) {
        taskById(tx, taskId)
        let link = first(tx.executeSql("SELECT * FROM provider_task_links WHERE task_id = ?", [taskId]))
        if (link) {
            return taskExternalLinkRecord(link)
        }
        // Compatibility for databases changed by the legacy CLI after this migration.
        const legacy = first(tx.executeSql("SELECT * FROM external_tasks WHERE task_id = ?", [taskId]))
        if (!legacy) {
            return null
        }
        return taskExternalLinkRecord({
            task_id: legacy.task_id, provider: legacy.provider, remote_id: legacy.remote_id,
            remote_key: legacy.remote_key, remote_url: legacy.remote_url, project_id: legacy.project_id,
            remote_updated_at: legacy.remote_updated_at, remote_revision: null,
            last_local_updated_at: legacy.last_local_updated_at, last_synced_at: legacy.last_synced_at,
            sync_state: legacy.sync_state, sync_error: null, assignee_ids_json: "[]",
            managed_baseline_json: "{}", remote_payload_json: legacy.remote_payload_json,
            created_at_utc: legacy.last_synced_at, updated_at_utc: legacy.last_synced_at
        })
    })
}

function listProviderTaskLinks(workspaceId, provider) {
    workspaceId = requireId(workspaceId, "Workspace ID")
    provider = requireProvider(provider)
    return read(function(tx) {
        workspaceById(tx, workspaceId)
        return rows(tx.executeSql(
            "SELECT provider_task_links.* FROM provider_task_links " +
            "JOIN tasks ON tasks.id = provider_task_links.task_id " +
            "JOIN categories ON categories.id = tasks.category_id " +
            "WHERE categories.workspace_id = ? AND provider_task_links.provider = ? " +
            "ORDER BY provider_task_links.task_id",
            [workspaceId, provider]
        )).map(taskExternalLinkRecord)
    })
}

function updateTaskExternalLink(input) {
    input = input || {}
    const taskId = requireId(input.taskId, "Task ID")
    return write(function(tx) {
        const task = taskById(tx, taskId)
        const existing = first(tx.executeSql("SELECT * FROM provider_task_links WHERE task_id = ?", [taskId]))
        const provider = input.provider === undefined
            ? (existing ? existing.provider : fail("Provider is required.")) : requireProvider(input.provider)
        const remoteId = input.remoteId === undefined ? (existing ? existing.remote_id : null)
            : (input.remoteId === null ? null : normalizedText(input.remoteId, "Remote ID", 200))
        const remoteKey = input.remoteKey === undefined ? (existing ? existing.remote_key : "") : String(input.remoteKey || "")
        const remoteUrl = input.remoteUrl === undefined ? (existing ? existing.remote_url : "") : String(input.remoteUrl || "")
        const projectId = input.projectId === undefined ? (existing ? existing.project_id : null)
            : (input.projectId === null ? null : normalizedText(input.projectId, "Remote project ID", 200))
        const remoteUpdatedAt = input.remoteUpdatedAt === undefined ? (existing ? existing.remote_updated_at : null)
            : (input.remoteUpdatedAt === null ? null : requireUtcInstant(input.remoteUpdatedAt, "Remote update time"))
        const remoteRevision = input.remoteRevision === undefined ? (existing ? existing.remote_revision : null)
            : (input.remoteRevision === null ? null : normalizedText(input.remoteRevision, "Remote revision", 200))
        const lastSyncedAt = input.lastSyncedAt === undefined ? (existing ? existing.last_synced_at : null)
            : (input.lastSyncedAt === null ? null : requireUtcInstant(input.lastSyncedAt, "Last sync time"))
        const syncState = input.syncState === undefined ? (existing ? existing.sync_state : (remoteId ? "in_sync" : "pending_create")) : requireSyncState(input.syncState)
        const syncError = input.syncError === undefined ? (existing ? existing.sync_error : null)
            : (input.syncError === null ? null : normalizedText(input.syncError, "Sync error", 2000))
        const assigneeIdsJson = jsonText(input.assigneeIds !== undefined ? input.assigneeIds : input.assigneeIdsJson, "Assignee IDs", existing ? existing.assignee_ids_json : "[]")
        const managedBaselineJson = jsonText(input.managedBaseline !== undefined ? input.managedBaseline : input.managedBaselineJson, "Managed baseline", existing ? existing.managed_baseline_json : "{}")
        const remotePayloadJson = jsonText(input.remotePayload !== undefined ? input.remotePayload : input.remotePayloadJson, "Remote payload", existing ? existing.remote_payload_json : "{}")
        const timestamp = nowUtc()
        tx.executeSql(
            "INSERT INTO provider_task_links (task_id, provider, remote_id, remote_key, remote_url, project_id, remote_updated_at, remote_revision, last_local_updated_at, last_synced_at, sync_state, sync_error, assignee_ids_json, managed_baseline_json, remote_payload_json, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(task_id) DO UPDATE SET provider = excluded.provider, remote_id = excluded.remote_id, remote_key = excluded.remote_key, remote_url = excluded.remote_url, project_id = excluded.project_id, remote_updated_at = excluded.remote_updated_at, remote_revision = excluded.remote_revision, last_local_updated_at = excluded.last_local_updated_at, last_synced_at = excluded.last_synced_at, sync_state = excluded.sync_state, sync_error = excluded.sync_error, assignee_ids_json = excluded.assignee_ids_json, managed_baseline_json = excluded.managed_baseline_json, remote_payload_json = excluded.remote_payload_json, updated_at_utc = excluded.updated_at_utc",
            [taskId, provider, remoteId, remoteKey, remoteUrl, projectId, remoteUpdatedAt, remoteRevision,
             task.updated_at_utc, lastSyncedAt, syncState, syncError, assigneeIdsJson, managedBaselineJson,
             remotePayloadJson, timestamp, timestamp]
        )
        return taskExternalLinkRecord(first(tx.executeSql("SELECT * FROM provider_task_links WHERE task_id = ?", [taskId])))
    })
}

function markPending(taskId, syncState, syncError) {
    taskId = requireId(taskId, "Task ID")
    syncState = requireSyncState(syncState)
    if (["pending_create", "pending_push", "error", "conflict"].indexOf(syncState) === -1) {
        fail("Only pending, error, or conflict states can be marked manually.")
    }
    return updateTaskExternalLink({ taskId: taskId, syncState: syncState,
        syncError: syncError === undefined ? null : syncError })
}

function createTask(input) {
    input = input || {}
    const categoryId = requireId(input.categoryId, "Category ID")
    const title = normalizedText(input.title, "Task title", 200)
    const details = typeof input.details === "string" ? input.details : ""
    if (codePointLength(details) > 20000) {
        fail("Task details must contain no more than 20,000 characters.")
    }
    return write(function(tx) {
        const category = activeCategoryById(tx, categoryId)
        const status = requireStatusForWorkspace(tx, category.workspace_id, input.status || "backlog")
        const timestamp = nowUtc()
        const task = {
            id: newId(), categoryId: categoryId, title: title, details: details, status: status,
            priority: requireTaskPriority(input.priority === undefined ? "none" : input.priority),
            position: nextPosition(tx, "tasks", "WHERE category_id = ?", [categoryId]),
            archivedAtUtc: null, completedAtUtc: workflowStatusById(tx, category.workspace_id, status).is_completed === 1 ? timestamp : null,
            createdAtUtc: timestamp, updatedAtUtc: timestamp
        }
        tx.executeSql(
            "INSERT INTO tasks (id, category_id, title, details, status, priority, position, archived_at_utc, completed_at_utc, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [task.id, task.categoryId, task.title, task.details, task.status, task.priority, task.position, task.archivedAtUtc,
             task.completedAtUtc, task.createdAtUtc, task.updatedAtUtc]
        )
        tx.executeSql(
            "INSERT INTO status_events (id, task_id, previous_status, status, occurred_at_utc, sequence, manually_edited, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, NULL, ?, ?, 1, 0, ?, ?)",
            [newId(), task.id, status, timestamp, timestamp, timestamp]
        )
        return task
    })
}

function updateTask(input) {
    input = input || {}
    const taskId = requireId(input.id, "Task ID")
    return write(function(tx) {
        const task = taskById(tx, taskId)
        const title = input.title === undefined ? task.title : normalizedText(input.title, "Task title", 200)
        const details = input.details === undefined ? task.details : input.details
        const priority = input.priority === undefined ? task.priority : requireTaskPriority(input.priority)
        if (typeof details !== "string" || codePointLength(details) > 20000) {
            fail("Task details must contain no more than 20,000 characters.")
        }
        tx.executeSql("UPDATE tasks SET title = ?, details = ?, priority = ?, updated_at_utc = ? WHERE id = ?", [title, details, priority, nowUtc(), taskId])
        return { id: taskId, title: title, details: details, priority: priority }
    })
}

function saveTask(input) {
    input = input || {}
    const taskId = requireId(input.id, "Task ID")
    const title = normalizedText(input.title, "Task title", 200)
    const details = typeof input.details === "string" ? input.details : ""
    const categoryId = requireId(input.categoryId, "Category ID")
    const status = requireStatusId(input.status)
    if (codePointLength(details) > 20000) {
        fail("Task details must contain no more than 20,000 characters.")
    }
    return write(function(tx) {
        const task = taskById(tx, taskId)
        const priority = input.priority === undefined ? task.priority : requireTaskPriority(input.priority)
        const currentCategory = activeCategoryById(tx, task.category_id)
        const category = activeCategoryById(tx, categoryId)
        requireStatusForWorkspace(tx, category.workspace_id, status)
        if (currentCategory.workspace_id !== category.workspace_id) {
            assertTaskWorkflowStatusesForWorkspace(tx, taskId, category.workspace_id)
        }
        const timestamp = nowUtc()
        let position = task.position
        if (task.category_id !== categoryId) {
            assertTaskMoveProviderCompatible(tx, task, categoryId)
            position = positionForMove(tx, categoryId, taskId, null, "before")
        }
        tx.executeSql(
            "UPDATE tasks SET title = ?, details = ?, priority = ?, category_id = ?, position = ?, updated_at_utc = ? WHERE id = ?",
            [title, details, priority, categoryId, position, timestamp, taskId]
        )
        if (task.status !== status) {
            tx.executeSql(
                "INSERT INTO status_events (id, task_id, previous_status, status, occurred_at_utc, sequence, manually_edited, created_at_utc, updated_at_utc) " +
                "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)",
                [newId(), taskId, task.status, status, timestamp, nextStatusSequence(tx, taskId), timestamp, timestamp]
            )
            const current = reconcileStatusHistory(tx, taskId)
            if (isCompletedStatusForTask(tx, taskId, current.status)) {
                closeActiveSessionForTask(tx, taskId, timestamp)
            }
        }
        return { id: taskId }
    })
}

function moveTask(input) {
    input = input || {}
    const taskId = requireId(input.taskId, "Task ID")
    const targetCategoryId = requireId(input.targetCategoryId, "Destination category ID")
    const targetTaskId = input.targetTaskId || null
    const placement = input.placement === "after" ? "after" : "before"
    return write(function(tx) {
        const task = taskById(tx, taskId)
        activeCategoryById(tx, task.category_id)
        const targetCategory = activeCategoryById(tx, targetCategoryId)
        if (targetTaskId === taskId) {
            return task.position
        }
        assertTaskMoveProviderCompatible(tx, task, targetCategoryId)
        assertTaskWorkflowStatusesForWorkspace(tx, taskId, targetCategory.workspace_id)
        const position = positionForMove(tx, targetCategoryId, taskId, targetTaskId, placement)
        tx.executeSql(
            "UPDATE tasks SET category_id = ?, position = ?, updated_at_utc = ? WHERE id = ?",
            [targetCategoryId, position, nowUtc(), taskId]
        )
        return position
    })
}

function archiveTask(taskId) {
    taskId = requireId(taskId, "Task ID")
    return write(function(tx) {
        taskById(tx, taskId)
        const timestamp = nowUtc()
        closeActiveSessionForTask(tx, taskId, timestamp)
        tx.executeSql("UPDATE tasks SET archived_at_utc = ?, updated_at_utc = ? WHERE id = ?", [timestamp, timestamp, taskId])
    })
}

function deleteTask(taskId) {
    taskId = requireId(taskId, "Task ID")
    return write(function(tx) {
        taskById(tx, taskId)
        tx.executeSql("DELETE FROM provider_task_links WHERE task_id = ?", [taskId])
        tx.executeSql("DELETE FROM external_tasks WHERE task_id = ?", [taskId])
        tx.executeSql("DELETE FROM work_sessions WHERE task_id = ?", [taskId])
        tx.executeSql("DELETE FROM status_events WHERE task_id = ?", [taskId])
        tx.executeSql("DELETE FROM tasks WHERE id = ?", [taskId])
    })
}

function changeStatus(taskId, status) {
    if (arguments.length > 2) {
        fail("Use status-history correction to change a historical status timestamp.")
    }
    taskId = requireId(taskId, "Task ID")
    status = requireStatusId(status)
    return write(function(tx) {
        const task = taskById(tx, taskId)
        const category = activeCategoryById(tx, task.category_id)
        requireStatusForWorkspace(tx, category.workspace_id, status)
        if (task.status === status) {
            return null
        }
        const timestamp = nowUtc()
        const eventId = newId()
        tx.executeSql(
            "INSERT INTO status_events (id, task_id, previous_status, status, occurred_at_utc, sequence, manually_edited, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)",
            [eventId, taskId, task.status, status, timestamp, nextStatusSequence(tx, taskId), timestamp, timestamp]
        )
        const current = reconcileStatusHistory(tx, taskId)
        if (isCompletedStatusForTask(tx, taskId, current.status)) {
            closeActiveSessionForTask(tx, taskId, timestamp)
        }
        return eventId
    })
}

function getActiveSession() {
    return read(function(tx) {
        return first(tx.executeSql(
            "SELECT work_sessions.*, tasks.title AS taskTitle FROM work_sessions JOIN tasks ON tasks.id = work_sessions.task_id " +
            "WHERE work_sessions.ended_at_utc IS NULL ORDER BY work_sessions.started_at_utc, work_sessions.id"
        ))
    })
}

function getActiveSessions() {
    return read(function(tx) {
        return rows(tx.executeSql(
            "SELECT work_sessions.*, tasks.title AS taskTitle FROM work_sessions JOIN tasks ON tasks.id = work_sessions.task_id " +
            "WHERE work_sessions.ended_at_utc IS NULL ORDER BY work_sessions.started_at_utc, work_sessions.id"
        ))
    })
}

function startTimer(taskId, timezoneId, startedAtUtc, allowConcurrentTimers) {
    taskId = requireId(taskId, "Task ID")
    timezoneId = requireTimezoneId(timezoneId)
    const timestamp = requireUtcInstant(startedAtUtc || nowUtc(), "Start time")
    const allowConcurrent = allowConcurrentTimers === true
    return write(function(tx) {
        taskById(tx, taskId)
        const active = activeSessions(tx)
        for (let index = 0; index < active.length; index += 1) {
            if (active[index].task_id === taskId) {
                if (!allowConcurrent) {
                    stopTimersExceptInTransaction(tx, taskId, timestamp)
                }
                return active[index]
            }
        }
        if (hasEndedSessionOverlap(tx, timestamp, "9999-12-31T23:59:59.999Z", null)) {
            fail("The active timer would overlap another session.")
        }
        if (!allowConcurrent) {
            stopTimersExceptInTransaction(tx, taskId, timestamp)
        }
        const session = {
            id: newId(), taskId: taskId, startedAtUtc: timestamp, endedAtUtc: null,
            timezoneId: timezoneId, manuallyEdited: 0, note: "", createdAtUtc: timestamp, updatedAtUtc: timestamp
        }
        tx.executeSql(
            "INSERT INTO work_sessions (id, task_id, started_at_utc, ended_at_utc, timezone_id, manually_edited, note, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, NULL, ?, 0, '', ?, ?)",
            [session.id, session.taskId, session.startedAtUtc, session.timezoneId, session.createdAtUtc, session.updatedAtUtc]
        )
        return session
    })
}

function stopTimer(taskId, stoppedAtUtc) {
    taskId = requireId(taskId, "Task ID")
    const timestamp = requireUtcInstant(stoppedAtUtc || nowUtc(), "End time")
    return write(function(tx) {
        return closeActiveSessionForTask(tx, taskId, timestamp)
    })
}

function stopTimersExcept(taskId, stoppedAtUtc) {
    taskId = requireId(taskId, "Task ID")
    const timestamp = requireUtcInstant(stoppedAtUtc || nowUtc(), "End time")
    return write(function(tx) {
        taskById(tx, taskId)
        if (!first(tx.executeSql("SELECT 1 FROM work_sessions WHERE task_id = ? AND ended_at_utc IS NULL", [taskId]))) {
            fail("The selected timer is no longer active.")
        }
        return stopTimersExceptInTransaction(tx, taskId, timestamp)
    })
}

function listWorkSessionsInTransaction(tx, taskId) {
    return rows(tx.executeSql("SELECT * FROM work_sessions WHERE task_id = ? ORDER BY started_at_utc DESC, id DESC", [taskId]))
}

function listWorkSessions(taskId) {
    taskId = requireId(taskId, "Task ID")
    return read(function(tx) { return listWorkSessionsInTransaction(tx, taskId) })
}

function hasSessionOverlap(tx, startedAtUtc, endedAtUtc, excludedSessionId) {
    let statement = "SELECT 1 FROM work_sessions WHERE started_at_utc < ? AND COALESCE(ended_at_utc, '9999-12-31T23:59:59.999Z') > ?"
    const parameters = [endedAtUtc, startedAtUtc]
    if (excludedSessionId) {
        statement += " AND id <> ?"
        parameters.push(excludedSessionId)
    }
    return first(tx.executeSql(statement, parameters)) !== null
}

function hasEndedSessionOverlap(tx, startedAtUtc, endedAtUtc, excludedSessionId) {
    let statement = "SELECT 1 FROM work_sessions WHERE ended_at_utc IS NOT NULL AND started_at_utc < ? AND ended_at_utc > ?"
    const parameters = [endedAtUtc, startedAtUtc]
    if (excludedSessionId) {
        statement += " AND id <> ?"
        parameters.push(excludedSessionId)
    }
    return first(tx.executeSql(statement, parameters)) !== null
}

function hasManualSessionOverlap(tx, startedAtUtc, endedAtUtc, excludedSessionId) {
    let statement = "SELECT 1 FROM work_sessions WHERE manually_edited = 1 AND started_at_utc < ? AND ended_at_utc > ?"
    const parameters = [endedAtUtc, startedAtUtc]
    if (excludedSessionId) {
        statement += " AND id <> ?"
        parameters.push(excludedSessionId)
    }
    return first(tx.executeSql(statement, parameters)) !== null
}

function createWorkSession(input) {
    input = input || {}
    const taskId = requireId(input.taskId, "Task ID")
    const startedAtUtc = requireUtcInstant(input.startedAtUtc, "Start time")
    const endedAtUtc = requireUtcInstant(input.endedAtUtc, "End time")
    const timezoneId = requireTimezoneId(input.timezoneId)
    if (endedAtUtc < startedAtUtc) {
        fail("The end time cannot be before the start time.")
    }
    return write(function(tx) {
        taskById(tx, taskId)
        if (hasSessionOverlap(tx, startedAtUtc, endedAtUtc, null)) {
            fail("A manual work session cannot overlap another session.")
        }
        const timestamp = nowUtc()
        const session = { id: newId(), taskId: taskId, startedAtUtc: startedAtUtc, endedAtUtc: endedAtUtc,
            timezoneId: timezoneId, note: input.note || "", manuallyEdited: 1, createdAtUtc: timestamp, updatedAtUtc: timestamp }
        tx.executeSql(
            "INSERT INTO work_sessions (id, task_id, started_at_utc, ended_at_utc, timezone_id, manually_edited, note, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)",
            [session.id, session.taskId, session.startedAtUtc, session.endedAtUtc, session.timezoneId, session.note, session.createdAtUtc, session.updatedAtUtc]
        )
        recalculateTrackedSeconds(tx, taskId)
        return session
    })
}

function updateWorkSession(input) {
    input = input || {}
    const sessionId = requireId(input.id, "Work session ID")
    return write(function(tx) {
        const session = first(tx.executeSql("SELECT * FROM work_sessions WHERE id = ?", [sessionId]))
        if (!session) {
            fail("The work session does not exist.")
        }
        const startedAtUtc = input.startedAtUtc === undefined ? session.started_at_utc : requireUtcInstant(input.startedAtUtc, "Start time")
        const endedAtUtc = input.endedAtUtc === undefined ? session.ended_at_utc : requireUtcInstant(input.endedAtUtc, "End time")
        if (!endedAtUtc || endedAtUtc < startedAtUtc) {
            fail("Manual work sessions must have an end time after their start time.")
        }
        const timezoneId = input.timezoneId === undefined ? session.timezone_id : requireTimezoneId(input.timezoneId)
        const note = input.note === undefined ? session.note : input.note
        if (typeof note !== "string" || codePointLength(note) > 20000) {
            fail("Work-session notes must contain no more than 20,000 characters.")
        }
        if (hasSessionOverlap(tx, startedAtUtc, endedAtUtc, sessionId)) {
            fail("A manual work session cannot overlap another session.")
        }
        tx.executeSql(
            "UPDATE work_sessions SET started_at_utc = ?, ended_at_utc = ?, timezone_id = ?, note = ?, manually_edited = 1, updated_at_utc = ? WHERE id = ?",
            [startedAtUtc, endedAtUtc, timezoneId, note, nowUtc(), sessionId]
        )
        recalculateTrackedSeconds(tx, session.task_id)
    })
}

function deleteWorkSession(sessionId) {
    sessionId = requireId(sessionId, "Work session ID")
    return write(function(tx) {
        const session = first(tx.executeSql("SELECT task_id FROM work_sessions WHERE id = ?", [sessionId]))
        tx.executeSql("DELETE FROM work_sessions WHERE id = ?", [sessionId])
        if (session) {
            recalculateTrackedSeconds(tx, session.task_id)
        }
    })
}

function listReportSessions(periodStartUtc, periodEndUtc, currentUtc, filter) {
    periodStartUtc = requireUtcInstant(periodStartUtc, "Report start")
    periodEndUtc = requireUtcInstant(periodEndUtc, "Report end")
    const activeEndUtc = requireUtcInstant(currentUtc || nowUtc(), "Report end")
    filter = filter || {}
    purgeExpiredTrash()
    return read(function(tx) {
        let query =
            "SELECT work_sessions.id AS sessionId, work_sessions.task_id AS taskId, tasks.title AS taskTitle, " +
            "categories.id AS categoryId, categories.name AS categoryName, categories.color AS categoryColor, " +
            "work_sessions.started_at_utc AS startedAtUtc, " +
            "COALESCE(work_sessions.ended_at_utc, ?) AS endedAtUtc, work_sessions.timezone_id AS timezoneId, " +
            "work_sessions.manually_edited AS manuallyEdited, " +
            "work_sessions.ended_at_utc IS NULL AS active " +
            "FROM work_sessions JOIN tasks ON tasks.id = work_sessions.task_id " +
            "JOIN categories ON categories.id = tasks.category_id " +
            "WHERE work_sessions.started_at_utc < ? " +
            "AND COALESCE(work_sessions.ended_at_utc, ?) > ? "
        const parameters = [activeEndUtc, periodEndUtc, activeEndUtc, periodStartUtc]
        if (filter.categoryId) {
            query += "AND categories.id = ? "
            parameters.push(filter.categoryId)
        }
        if (filter.taskId) {
            query += "AND tasks.id = ? "
            parameters.push(filter.taskId)
        }
        query += "ORDER BY work_sessions.started_at_utc, work_sessions.id"
        return rows(tx.executeSql(query, parameters))
    })
}

function listStatusEventsInTransaction(tx, taskId) {
    return rows(tx.executeSql(
        "SELECT * FROM status_events WHERE task_id = ? ORDER BY occurred_at_utc DESC, sequence DESC, id DESC",
        [taskId]
    ))
}

function listStatusEvents(taskId) {
    taskId = requireId(taskId, "Task ID")
    return read(function(tx) { return listStatusEventsInTransaction(tx, taskId) })
}

function updateStatusEvent(input) {
    input = input || {}
    const eventId = requireId(input.id, "Status event ID")
    const status = requireStatusId(input.status)
    const occurredAtUtc = requireUtcInstant(input.occurredAtUtc, "Status event time")
    return write(function(tx) {
        const event = first(tx.executeSql("SELECT * FROM status_events WHERE id = ?", [eventId]))
        if (!event) {
            fail("The status event does not exist.")
        }
        const task = taskById(tx, event.task_id)
        const category = activeCategoryById(tx, task.category_id)
        requireStatusForWorkspace(tx, category.workspace_id, status)
        tx.executeSql(
            "UPDATE status_events SET status = ?, occurred_at_utc = ?, manually_edited = 1, updated_at_utc = ? WHERE id = ?",
            [status, occurredAtUtc, nowUtc(), eventId]
        )
        const current = reconcileStatusHistory(tx, event.task_id)
        if (isCompletedStatusForTask(tx, event.task_id, current.status)) {
            closeActiveSessionForTask(tx, event.task_id, nowUtc())
        }
    })
}

function deleteStatusEvent(eventId) {
    eventId = requireId(eventId, "Status event ID")
    return write(function(tx) {
        const event = first(tx.executeSql("SELECT * FROM status_events WHERE id = ?", [eventId]))
        if (!event) {
            return
        }
        const count = tx.executeSql("SELECT COUNT(*) AS count FROM status_events WHERE task_id = ?", [event.task_id])
        if (count.rows.item(0).count < 2) {
            fail("A task must retain its initial status event.")
        }
        tx.executeSql("DELETE FROM status_events WHERE id = ?", [eventId])
        const current = reconcileStatusHistory(tx, event.task_id)
        if (isCompletedStatusForTask(tx, event.task_id, current.status)) {
            closeActiveSessionForTask(tx, event.task_id, nowUtc())
        }
    })
}
