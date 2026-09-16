.pragma library

.import QtQuick.LocalStorage as Sql
.import "Migrations.js" as Migrations

// Keep this established LocalStorage name so rebranding does not orphan user data.
const DATABASE_ID = "io.github.ownisticapps.worktodo"
const POSITION_GAP = 1024
const POSITION_OFFSET = 1000000000
const TRASH_RETENTION_DAYS = 30
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000
const STATUSES = ["backlog", "ready", "in_progress", "blocked", "completed"]

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

function requireStatus(status) {
    if (STATUSES.indexOf(status) === -1) {
        fail("The task status is invalid.")
    }
    return status
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
        [previousStatus, previousStatus === "completed" ? current.occurred_at_utc : null, nowUtc(), taskId]
    )
    return { status: previousStatus, occurredAtUtc: current.occurred_at_utc }
}

function positionForCategoryMove(tx, categoryId, targetCategoryId, placement) {
    const ordered = rows(tx.executeSql(
        "SELECT id, position FROM categories WHERE trashed_at_utc IS NULL AND id <> ? ORDER BY position, created_at_utc, id",
        [categoryId]
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
        tx.executeSql("UPDATE categories SET position = position + ? WHERE trashed_at_utc IS NULL", [POSITION_OFFSET])
        const categories = rows(tx.executeSql(
            "SELECT id FROM categories WHERE trashed_at_utc IS NULL ORDER BY position, created_at_utc, id"
        ))
        for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex += 1) {
            tx.executeSql("UPDATE categories SET position = ? WHERE id = ?", [(categoryIndex + 1) * POSITION_GAP, categories[categoryIndex].id])
        }
        return positionForCategoryMove(tx, categoryId, targetCategoryId, placement)
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

function listCategories() {
    purgeExpiredTrash()
    return read(function(tx) {
        return rows(tx.executeSql("SELECT * FROM categories WHERE trashed_at_utc IS NULL ORDER BY position, created_at_utc, id"))
    })
}

function listTrashedCategories() {
    purgeExpiredTrash()
    return read(function(tx) {
        return rows(tx.executeSql("SELECT * FROM categories WHERE trashed_at_utc IS NOT NULL ORDER BY trashed_at_utc DESC, position, id"))
    })
}

function createCategory(input) {
    input = input || {}
    const name = normalizedText(input.name, "Category name", 100)
    const color = normalizedText(input.color || "#3daee9", "Category color", 32)
    return write(function(tx) {
        const timestamp = nowUtc()
        const category = {
            id: newId(),
            name: name,
            color: color,
            position: nextPosition(tx, "categories", "WHERE trashed_at_utc IS NULL", []),
            collapsed: input.collapsed ? 1 : 0,
            created_at_utc: timestamp,
            updated_at_utc: timestamp
        }
        tx.executeSql(
            "INSERT INTO categories (id, name, color, position, collapsed, created_at_utc, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [category.id, category.name, category.color, category.position, category.collapsed, category.created_at_utc, category.updated_at_utc]
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
        const timestamp = nowUtc()
        tx.executeSql(
            "UPDATE categories SET name = ?, color = ?, collapsed = ?, updated_at_utc = ? WHERE id = ?",
            [name, color, collapsed, timestamp, categoryId]
        )
        return { id: categoryId, name: name, color: color, collapsed: collapsed }
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
        const position = positionForCategoryMove(tx, categoryId, targetCategoryId, placement)
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
        const position = nextPosition(tx, "categories", "WHERE trashed_at_utc IS NULL", [])
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
    for (let index = 0; index < statuses.length; index += 1) {
        requireStatus(statuses[index])
    }
    return read(function(tx) {
        const clauses = ["categories.trashed_at_utc IS NULL", showArchived ? "1 = 1" : "tasks.archived_at_utc IS NULL"]
        const parameters = []
        if (statuses.length > 0) {
            clauses.push("tasks.status IN (" + statuses.map(function() { return "?" }).join(", ") + ")")
            for (let index = 0; index < statuses.length; index += 1) {
                parameters.push(statuses[index])
            }
        }
        return rows(tx.executeSql(
            "SELECT tasks.id AS taskId, tasks.category_id AS categoryId, categories.name AS categoryName, " +
            "categories.color AS categoryColor, categories.collapsed AS categoryCollapsed, tasks.title, tasks.details, " +
            "tasks.status, tasks.position, tasks.archived_at_utc AS archivedAtUtc, " +
            "tasks.tracked_seconds AS trackedSeconds, " +
            "active_session.started_at_utc AS activeStartedAt " +
            "FROM tasks JOIN categories ON categories.id = tasks.category_id " +
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
            "SELECT tasks.*, categories.name AS category_name, categories.color AS category_color, " +
            "tasks.tracked_seconds AS trackedSeconds, " +
            "(SELECT started_at_utc FROM work_sessions WHERE task_id = tasks.id AND ended_at_utc IS NULL) AS activeStartedAt " +
            "FROM tasks " +
            "JOIN categories ON categories.id = tasks.category_id WHERE tasks.id = ?",
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

function createTask(input) {
    input = input || {}
    const categoryId = requireId(input.categoryId, "Category ID")
    const title = normalizedText(input.title, "Task title", 200)
    const details = typeof input.details === "string" ? input.details : ""
    if (codePointLength(details) > 20000) {
        fail("Task details must contain no more than 20,000 characters.")
    }
    const status = requireStatus(input.status || "backlog")
    return write(function(tx) {
        activeCategoryById(tx, categoryId)
        const timestamp = nowUtc()
        const task = {
            id: newId(), categoryId: categoryId, title: title, details: details, status: status,
            position: nextPosition(tx, "tasks", "WHERE category_id = ?", [categoryId]),
            archivedAtUtc: null, completedAtUtc: status === "completed" ? timestamp : null,
            createdAtUtc: timestamp, updatedAtUtc: timestamp
        }
        tx.executeSql(
            "INSERT INTO tasks (id, category_id, title, details, status, position, archived_at_utc, completed_at_utc, created_at_utc, updated_at_utc) " +
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [task.id, task.categoryId, task.title, task.details, task.status, task.position, task.archivedAtUtc,
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
        if (typeof details !== "string" || codePointLength(details) > 20000) {
            fail("Task details must contain no more than 20,000 characters.")
        }
        tx.executeSql("UPDATE tasks SET title = ?, details = ?, updated_at_utc = ? WHERE id = ?", [title, details, nowUtc(), taskId])
        return { id: taskId, title: title, details: details }
    })
}

function saveTask(input) {
    input = input || {}
    const taskId = requireId(input.id, "Task ID")
    const title = normalizedText(input.title, "Task title", 200)
    const details = typeof input.details === "string" ? input.details : ""
    const categoryId = requireId(input.categoryId, "Category ID")
    const status = requireStatus(input.status)
    if (codePointLength(details) > 20000) {
        fail("Task details must contain no more than 20,000 characters.")
    }
    return write(function(tx) {
        const task = taskById(tx, taskId)
        activeCategoryById(tx, task.category_id)
        activeCategoryById(tx, categoryId)
        const timestamp = nowUtc()
        let position = task.position
        if (task.category_id !== categoryId) {
            position = positionForMove(tx, categoryId, taskId, null, "before")
        }
        tx.executeSql(
            "UPDATE tasks SET title = ?, details = ?, category_id = ?, position = ?, updated_at_utc = ? WHERE id = ?",
            [title, details, categoryId, position, timestamp, taskId]
        )
        if (task.status !== status) {
            tx.executeSql(
                "INSERT INTO status_events (id, task_id, previous_status, status, occurred_at_utc, sequence, manually_edited, created_at_utc, updated_at_utc) " +
                "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)",
                [newId(), taskId, task.status, status, timestamp, nextStatusSequence(tx, taskId), timestamp, timestamp]
            )
            const current = reconcileStatusHistory(tx, taskId)
            if (current.status === "completed") {
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
        activeCategoryById(tx, targetCategoryId)
        if (targetTaskId === taskId) {
            return task.position
        }
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
    status = requireStatus(status)
    return write(function(tx) {
        const task = taskById(tx, taskId)
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
        if (current.status === "completed") {
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

function listReportSessions(periodStartUtc, periodEndUtc, currentUtc) {
    periodStartUtc = requireUtcInstant(periodStartUtc, "Report start")
    periodEndUtc = requireUtcInstant(periodEndUtc, "Report end")
    const activeEndUtc = requireUtcInstant(currentUtc || nowUtc(), "Report end")
    purgeExpiredTrash()
    return read(function(tx) {
        return rows(tx.executeSql(
            "SELECT work_sessions.id AS sessionId, work_sessions.task_id AS taskId, tasks.title AS taskTitle, " +
            "categories.id AS categoryId, categories.name AS categoryName, categories.color AS categoryColor, " +
            "work_sessions.started_at_utc AS startedAtUtc, " +
            "COALESCE(work_sessions.ended_at_utc, ?) AS endedAtUtc, work_sessions.timezone_id AS timezoneId, " +
            "work_sessions.manually_edited AS manuallyEdited " +
            "FROM work_sessions JOIN tasks ON tasks.id = work_sessions.task_id " +
            "JOIN categories ON categories.id = tasks.category_id " +
            "WHERE work_sessions.started_at_utc < ? " +
            "AND COALESCE(work_sessions.ended_at_utc, ?) > ? " +
            "ORDER BY work_sessions.started_at_utc, work_sessions.id",
            [activeEndUtc, periodEndUtc, activeEndUtc, periodStartUtc]
        ))
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
    const status = requireStatus(input.status)
    const occurredAtUtc = requireUtcInstant(input.occurredAtUtc, "Status event time")
    return write(function(tx) {
        const event = first(tx.executeSql("SELECT * FROM status_events WHERE id = ?", [eventId]))
        if (!event) {
            fail("The status event does not exist.")
        }
        tx.executeSql(
            "UPDATE status_events SET status = ?, occurred_at_utc = ?, manually_edited = 1, updated_at_utc = ? WHERE id = ?",
            [status, occurredAtUtc, nowUtc(), eventId]
        )
        const current = reconcileStatusHistory(tx, event.task_id)
        if (current.status === "completed") {
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
        if (current.status === "completed") {
            closeActiveSessionForTask(tx, event.task_id, nowUtc())
        }
    })
}
