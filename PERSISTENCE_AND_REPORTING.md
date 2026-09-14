# Persistence and reporting design

This document defines the version 1 SQLite schema, storage invariants, migration rules, timer transitions, and report calculations.

## 1. Storage choice

Version 1 uses `QtQuick.LocalStorage`, which provides synchronous SQLite access from QML JavaScript.

The expected data volume is small enough for local synchronous transactions. Database access must remain behind a repository module so a later release can move storage to `Qt6::Sql` without changing interface components.

Do not store application data in KConfig. KConfig stores widget preferences only.

## 2. Schema

### 2.1 Schema migrations

```sql
CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at_utc TEXT NOT NULL
);
```

### 2.2 Categories

```sql
CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    position INTEGER NOT NULL,
    collapsed INTEGER NOT NULL DEFAULT 0,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT NOT NULL
);

CREATE UNIQUE INDEX categories_position_idx
    ON categories(position);
```

### 2.3 Tasks

```sql
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    category_id TEXT NOT NULL,
    title TEXT NOT NULL,
    details TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL,
    position INTEGER NOT NULL,
    archived_at_utc TEXT,
    completed_at_utc TEXT,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT NOT NULL,
    FOREIGN KEY (category_id) REFERENCES categories(id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CHECK (length(trim(title)) BETWEEN 1 AND 200),
    CHECK (status IN ('backlog', 'ready', 'in_progress', 'blocked', 'completed'))
);

CREATE UNIQUE INDEX tasks_category_position_idx
    ON tasks(category_id, position);

CREATE INDEX tasks_status_idx
    ON tasks(status);

CREATE INDEX tasks_archived_status_idx
    ON tasks(archived_at_utc, status);
```

### 2.4 Work sessions

```sql
CREATE TABLE work_sessions (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    started_at_utc TEXT NOT NULL,
    ended_at_utc TEXT,
    timezone_id TEXT NOT NULL,
    manually_edited INTEGER NOT NULL DEFAULT 0,
    note TEXT NOT NULL DEFAULT '',
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT NOT NULL,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CHECK (ended_at_utc IS NULL OR ended_at_utc >= started_at_utc)
);

CREATE INDEX work_sessions_task_start_idx
    ON work_sessions(task_id, started_at_utc);

CREATE INDEX work_sessions_period_idx
    ON work_sessions(started_at_utc, ended_at_utc);
```

SQLite supports a partial unique index that can enforce one active timer:

```sql
CREATE UNIQUE INDEX one_active_work_session_idx
    ON work_sessions((1))
    WHERE ended_at_utc IS NULL;
```

The implementation must verify that the SQLite version used through Qt accepts this expression index. If the runtime rejects the index, enforce the invariant in every write transaction and add an initialization integrity check.

### 2.5 Status events

```sql
CREATE TABLE status_events (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    previous_status TEXT,
    status TEXT NOT NULL,
    occurred_at_utc TEXT NOT NULL,
    manually_edited INTEGER NOT NULL DEFAULT 0,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT NOT NULL,
    FOREIGN KEY (task_id) REFERENCES tasks(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CHECK (previous_status IS NULL OR previous_status IN (
        'backlog', 'ready', 'in_progress', 'blocked', 'completed'
    )),
    CHECK (status IN (
        'backlog', 'ready', 'in_progress', 'blocked', 'completed'
    ))
);

CREATE INDEX status_events_task_time_idx
    ON status_events(task_id, occurred_at_utc);
```

## 3. Database initialization

Initialization must perform these actions in order:

1. Open the database with a product-specific identifier.
2. Enable foreign-key enforcement with `PRAGMA foreign_keys = ON`.
3. Create the migration table if it does not exist.
4. Read the latest applied migration version.
5. Apply each missing migration in order.
6. Verify that no more than one work session is active.
7. Load preferences and the initial task view.

Do not mark a migration as applied until all statements in that migration succeed.

## 4. Ordering model

Use integer positions with gaps, for example `1024`, `2048`, and `3072`. A gap-based scheme avoids updating every task during most reorders.

### 4.1 Insert between tasks

Given positions `1024` and `2048`, assign the inserted task position `1536`.

### 4.2 Rebalance

Rebalance a category when no integer exists between the destination neighbors. Rebalancing assigns positions in multiples of `1024` within one transaction.

### 4.3 Move across categories

Moving a task across categories must update:

- `category_id`.
- `position` within the destination category.
- `updated_at_utc`.

The move operation must use stable task and category identifiers. A filtered visible index is not a persistent ordering key.

### 4.4 Filter behavior

Reordering while a status filter is active affects the dragged task relative to the visible destination task. Hidden tasks retain their existing positions.

Example:

```text
Stored order: A, B, C, D
Visible filter: A, C
Move C before A
Result: C, A, B, D
```

The implementation must document and test this policy. An alternative insertion policy is valid only if the product decision changes before implementation.

## 5. Time-tracking state machine

The persisted state is intentionally small:

- No row with `ended_at_utc IS NULL`: no active timer.
- One row with `ended_at_utc IS NULL`: that task has the active timer.

Pause and stop both close the active work session. Resume starts a new session for the same task. This model represents breaks as gaps between work sessions.

### 5.1 Start with no active session

1. Insert a work session with a start timestamp and no end timestamp.
2. Commit the transaction.
3. Update the visible model.

### 5.2 Switch active task

1. Begin a transaction.
2. Close the existing active session at the switch timestamp.
3. Insert a new active session for the selected task with the same switch timestamp.
4. Commit the transaction.
5. Update both affected task rows.

The shared timestamp prevents a gap or overlap caused by separate clock reads.

### 5.3 Stop or pause

1. Begin a transaction.
2. Find the active work session.
3. Set its end timestamp if it remains open.
4. Commit the transaction.
5. Update the affected task row.

The stop operation must be idempotent. A repeated stop request must not change a closed session.

### 5.4 Restart recovery

At initialization, query the active work session. Calculate displayed elapsed time from the persisted start timestamp and the current UTC time. Do not create a new session during recovery.

### 5.5 Sleep and long-session behavior

The default model counts time while the computer sleeps because the persisted interval remains open. This behavior supports deliberate long-running tracking but can also create accidental time.

Display a correction prompt when an active interval exceeds the configured unusual-session threshold. The default threshold is 16 hours. The user can keep the interval, change the end time, or discard the invalid portion.

## 6. Manual corrections

Manual corrections operate on ledger entries, not cached totals.

The user can:

- Create a work session with an explicit date, start time, end time, timezone, and optional note.
- Edit a work session’s start time, end time, timezone, and note.
- Delete a work session.
- Edit a status event’s status and timestamp.
- Delete a redundant status event when the resulting history remains valid.

Set `manually_edited` to `1` after a user changes an automatically created entry.

After any history correction:

1. Recalculate the affected task total.
2. Recalculate the active report when the edited interval intersects its date range.
3. Update the task’s current status from the latest valid status event when status history changes.

## 7. Timezone model

Store timestamps in UTC and store an IANA timezone identifier on each work session.

The report accepts an explicit report timezone. Default the preference to the current system timezone when no preference is configured.

The selected report timezone determines:

- Local midnight boundaries.
- Week boundaries.
- Month boundaries.
- Day labels.
- Daylight-saving transitions.

The report must not calculate a local date by applying a fixed UTC offset. A timezone can change offset during a reporting period.

## 8. Interval splitting

A work session can cross one or more local calendar boundaries. Reports must divide the session into non-overlapping segments before aggregation.

### 8.1 Algorithm

For each work session that intersects the report range:

1. Clamp the UTC interval to the report’s UTC range.
2. Convert the segment start to the report timezone.
3. Find the next local midnight in the report timezone.
4. Convert that boundary to UTC.
5. Add the duration from the current start to the earlier of the session end or next midnight.
6. Continue from the boundary until the session ends.

Use actual instants for duration. Do not subtract formatted local clock values because a daylight-saving transition can repeat or skip local times.

### 8.2 Active session in reports

When a report includes the current date, use the current UTC time as the temporary end of the active session. Do not persist this temporary value.

### 8.3 Overlap rule

The one-active-session invariant prevents automatically created overlaps. Manual edits can still introduce an overlap.

Version 1 should reject a manual work session that overlaps another session. If overlapping work becomes a future requirement, reports must define whether overlapping seconds count once or once per task.

## 9. Weekly report

Input:

```text
week start local date
first day of week
report timezone
optional category filter
optional task filter
```

Output:

```text
period start and end
total seconds
seconds by local date
seconds by category
seconds by task
daily seconds by category for stacked bars
```

The report range is half-open: `[periodStart, periodEnd)`. Work at exactly the next week’s start belongs to the next week.

## 10. Monthly report

Input:

```text
year and month
report timezone
optional category filter
optional task filter
```

Output:

```text
period start and end
total seconds
seconds by local date
seconds by calendar week
seconds by category
seconds by task
daily seconds by category for stacked bars
```

The month range is half-open: `[firstLocalMidnight, nextMonthFirstLocalMidnight)`.

## 11. Totals and caching

Treat work sessions as the source of truth. Calculate totals from work sessions.

Version 1 should not persist a mutable `tracked_seconds` total on the task row. The visible model can cache a calculated total in memory. Reload or invalidate that cache after a work-session write.

A later release can add a materialized total if measured performance requires it. Such a total must be rebuildable from the work-session ledger.

## 12. Delete and archive behavior

Archiving a task:

- Sets `archived_at_utc`.
- Retains work sessions and status events.
- Excludes the task from normal task views.
- Includes its historical time in reports.

Deleting a task:

- Deletes the task.
- Deletes its work sessions through the foreign-key cascade.
- Deletes its status events through the foreign-key cascade.
- Requires a confirmation that states that time and status history will also be deleted.

Deleting a category:

- Must not cascade automatically to tasks.
- Requires the user to move, archive, or delete contained tasks first.

## 13. Integrity checks

Run these checks during development and before backup or export:

- No more than one active work session exists.
- Every task references an existing category.
- Every work session references an existing task.
- Every status event references an existing task.
- Task positions are unique within each category.
- Category positions are unique.
- Closed work sessions end at or after they start.
- Current task status matches the latest effective status event.

Reference: [Qt Quick Local Storage](https://doc.qt.io/qt-6/qtquick-localstorage-qmlmodule.html)

