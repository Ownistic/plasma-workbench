# Product requirements document: Work Todo Plasmoid

**Status:** Draft 1  
**Target platform:** KDE Plasma 6 on CachyOS and compatible Linux distributions  
**Product type:** Desktop Plasma widget, also called a plasmoid  
**Primary user:** A software developer organizing personal work tasks  
**Document date:** 2026-09-14

## 1. Product summary

Work Todo Plasmoid is a local-first task and work-time tracker displayed directly on the KDE Plasma desktop. The widget combines a card-based task list, status history, category organization, drag-and-drop ordering, task details, and weekly or monthly work reports.

The widget must make the current work queue visible without requiring a browser or a separate task-management service. The widget must operate without a network connection and must keep all task data on the local device.

## 2. Problem statement

General todo applications often separate task planning from time tracking. They also require the user to open a separate application or web page. This separation makes it harder to see the current work queue, record task transitions, and understand how work time was distributed.

The user needs one desktop surface that answers four questions:

1. What work is ready, active, blocked, or completed?
2. Which task is being tracked now?
3. How much time was spent on each task and category?
4. What did the work week or month look like?

## 3. Goals

### 3.1 Primary goals

- Display an actionable task list directly on the Plasma desktop.
- Track task status and retain status history.
- Track time by task through start, pause, resume, and stop actions.
- Permit manual corrections to time entries and status events.
- Organize tasks with colored categories and category headers.
- Filter tasks by one or more statuses.
- Reorder tasks and categories through drag-and-drop.
- Display weekly and monthly work-time reports.
- Store all data locally and support offline operation.
- Recover an active timer after Plasma or the computer restarts.

### 3.2 Secondary goals

- Match the active Plasma color scheme and scale correctly on HiDPI displays.
- Support keyboard navigation and accessible labels.
- Keep the first version installable as a normal, uncompiled Plasma package.
- Preserve an architecture that can adopt a Qt/C++ backend later.

## 4. Non-goals for version 1

- Team collaboration or task assignment.
- Cloud synchronization.
- Mobile or web clients.
- Calendar synchronization.
- Notifications for due dates.
- Pomodoro or mandatory break enforcement.
- Dependencies between tasks.
- File attachments.
- Rich-text editing beyond plain text or Markdown-compatible text.
- Simultaneous active timers.
- Live synchronization between multiple widget instances.

## 5. Product terminology

| Term | Meaning |
| --- | --- |
| Task | A unit of work tracked by the user. |
| Category | A named, colored group that owns zero or more tasks. |
| Category header | The visible heading that represents a category in the task list. |
| Status | The current workflow state of a task. |
| Status event | A timestamped record of a task entering a status. |
| Work session | One continuous interval of tracked time for one task. |
| Active timer | A work session that has a start time and no end time. |
| Manual correction | A user-authorized edit to a work session or status event. |
| Report timezone | The timezone used to divide work sessions into calendar days and reporting periods. |

## 6. Default workflow

Version 1 provides these default statuses:

1. Backlog
2. Ready
3. In progress
4. Blocked
5. Completed

The status names are fixed in version 1. A later release can make statuses configurable after the product establishes migration and reporting rules for custom workflows.

## 7. User experience

### 7.1 Desktop layout

The full desktop representation contains these regions:

1. A header with the product title, current tracked time, and primary actions.
2. A status-filter row.
3. A scrollable task list grouped by category headers.
4. A navigation action for weekly and monthly reports.

The widget must display its full representation when Plasma gives it enough desktop space. A panel placement can use a compact representation that opens the full view.

### 7.2 Task card

Each card displays:

- Task title.
- Category color.
- Current status.
- Total tracked time.
- Active timer indicator when applicable.
- Start, pause, or resume action as applicable.
- Drag handle.
- A control that opens task details.

The task card must not display the entire task description. The details view provides the complete description and history.

### 7.3 Task details

Opening a task displays:

- Editable title.
- Editable description.
- Category selector.
- Status selector.
- Total tracked time.
- Start, pause, resume, and stop actions as applicable.
- Work-session history.
- Status history.
- Actions to edit or delete individual history entries.
- Archive and delete actions.

The interface must distinguish **Archive task** from **Delete task**. Archiving retains history. Deleting removes the task after a confirmation that states the effect on associated history.

### 7.4 Reports

The weekly report displays:

- Seven daily work-time bars.
- Total tracked time for the week.
- Time grouped by category.
- Time grouped by task.
- Previous-week and next-week navigation.

The monthly report displays:

- Daily bars or weekly aggregate bars, based on available width.
- Total tracked time for the month.
- Time grouped by category.
- Time grouped by task.
- Previous-month and next-month navigation.

Selecting a report bar opens the task-level breakdown for that period.

## 8. Functional requirements

Priority uses `P0` for release-blocking behavior, `P1` for important version 1 behavior, and `P2` for a later release.

### 8.1 Task management

| ID | Priority | Requirement |
| --- | --- | --- |
| TASK-001 | P0 | The user can create a task with a title, category, status, and optional description. |
| TASK-002 | P0 | The user can edit every task field. |
| TASK-003 | P0 | The user can open a card to view task details. |
| TASK-004 | P0 | The user can archive a task without deleting its history. |
| TASK-005 | P1 | The user can delete a task after a consequence-specific confirmation. |
| TASK-006 | P1 | The widget can hide or show archived tasks. |
| TASK-007 | P1 | Task titles must contain 1 through 200 Unicode characters after trimming. |
| TASK-008 | P1 | Task descriptions must support at least 20,000 Unicode characters. |

### 8.2 Categories and ordering

| ID | Priority | Requirement |
| --- | --- | --- |
| CAT-001 | P0 | The user can create, rename, recolor, and reorder categories. |
| CAT-002 | P0 | Each category appears as a colored header in the grouped task list. |
| CAT-003 | P0 | The user can reorder tasks within a category through drag-and-drop. |
| CAT-004 | P0 | The user can drag a task into another category. |
| CAT-005 | P0 | The widget persists task and category order immediately. |
| CAT-006 | P1 | The user can collapse or expand a category. |
| CAT-007 | P1 | Category deletion requires the user to move, archive, or delete contained tasks. |

### 8.3 Status tracking and filtering

| ID | Priority | Requirement |
| --- | --- | --- |
| STATUS-001 | P0 | Each task has exactly one current status. |
| STATUS-002 | P0 | Each status change creates a timestamped status event. |
| STATUS-003 | P0 | The user can filter the task list by one or more statuses. |
| STATUS-004 | P0 | The user can clear all status filters. |
| STATUS-005 | P1 | The user can edit the status and timestamp of a historical status event. |
| STATUS-006 | P1 | Manually edited status events display a manual-correction indicator. |
| STATUS-007 | P1 | The widget records the previous status when the user changes the current status. |

### 8.4 Time tracking

| ID | Priority | Requirement |
| --- | --- | --- |
| TIME-001 | P0 | The user can start time tracking from a task card or task details. |
| TIME-002 | P0 | The user can pause or stop the active timer. |
| TIME-003 | P0 | The widget permits no more than one active timer. |
| TIME-004 | P0 | Starting another task closes the current session and starts a new session in one database transaction. |
| TIME-005 | P0 | The visible elapsed time refreshes at least once per second while a timer is active. |
| TIME-006 | P0 | Persisted timestamps, not refresh-timer ticks, determine elapsed time. |
| TIME-007 | P0 | An active session remains recoverable after a Plasma restart or computer restart. |
| TIME-008 | P1 | The user can create, edit, and delete a manual work session. |
| TIME-009 | P1 | Manual sessions require a date, start time, end time, and report timezone. |
| TIME-010 | P1 | The widget rejects work sessions with an end time before the start time. |
| TIME-011 | P1 | The widget displays a warning before accepting an unusually long session, with a default threshold of 16 hours. |

### 8.5 Reports

| ID | Priority | Requirement |
| --- | --- | --- |
| REPORT-001 | P0 | The widget calculates a weekly report for the selected calendar week. |
| REPORT-002 | P0 | The widget calculates a monthly report for the selected calendar month. |
| REPORT-003 | P0 | Reports include completed and archived tasks when those tasks have work sessions in the selected period. |
| REPORT-004 | P0 | Reports split a session at local midnight before grouping time by date. |
| REPORT-005 | P0 | Reports split sessions at week and month boundaries. |
| REPORT-006 | P0 | Reports use the configured report timezone. |
| REPORT-007 | P1 | Reports display totals by date, task, and category. |
| REPORT-008 | P1 | Report totals include manual corrections. |
| REPORT-009 | P2 | The user can export a report as CSV. |

### 8.6 Preferences

| ID | Priority | Requirement |
| --- | --- | --- |
| PREF-001 | P1 | The user can select the first day of the week. |
| PREF-002 | P1 | The user can select a report timezone. |
| PREF-003 | P1 | The user can choose the default status filter. |
| PREF-004 | P1 | The user can show or hide archived tasks. |
| PREF-005 | P1 | The user can choose 12-hour or 24-hour time display. |
| PREF-006 | P1 | Preferences persist through Plasma configuration. |

## 9. Data requirements

The database must store these primary entities:

- Categories.
- Tasks.
- Work sessions.
- Status events.
- Schema migrations.

The database must use stable text identifiers. The interface must not use a list index as a persistent task identity.

The database must store timestamps in UTC. Each work session must also store the timezone used when the session was created or corrected.

Detailed schema and calculation rules are defined in [PERSISTENCE_AND_REPORTING.md](docs/PERSISTENCE_AND_REPORTING.md).

## 10. Quality requirements

### 10.1 Performance

- The widget should display the initial task list within 500 milliseconds after its QML component completes on the target machine.
- A normal create, edit, status change, or reorder operation should complete within 100 milliseconds for 5,000 tasks and 100,000 work sessions.
- The weekly report should complete within 250 milliseconds for 100,000 work sessions.
- The monthly report should complete within 500 milliseconds for 100,000 work sessions.
- The visible one-second timer refresh must not write to the database.

These values are engineering targets. Implementation tests must confirm or revise the targets.

### 10.2 Reliability

- Every multi-record operation must use a database transaction.
- Schema migrations must be idempotent or version-gated.
- A failed write must leave the in-memory model consistent with the stored data.
- The widget must not lose an active session when the visual delegate is destroyed.
- The widget must recover from malformed optional preference values by using documented defaults.

### 10.3 Accessibility

- Every icon-only control must have an accessible name.
- Keyboard focus order must follow the visible reading order.
- Status and timer state must not depend on color alone.
- Category colors must retain readable text contrast in light and dark Plasma themes.
- Drag-and-drop ordering must have keyboard-accessible Move up, Move down, and Move to category alternatives.

### 10.4 Privacy and security

- Version 1 must make no network requests.
- Task data remains in a local SQLite database.
- The documentation must state that the database is not encrypted by the widget.
- The widget must use bound SQL parameters for user-provided values.
- Diagnostic logs must not contain task descriptions.

## 11. Technical constraints

- Target KDE Plasma 6.
- Set `X-Plasma-API-Minimum-Version` to `6.0` unless an implemented API requires a higher version.
- Use `PlasmoidItem` as the root QML type.
- Use versionless QML imports for Qt 6 and Plasma 6 modules.
- Implement version 1 as an uncompiled Plasma package when feasible.
- Use `QtQuick.LocalStorage` for version 1 application data.
- Use `plasmoid.configuration` only for preferences.
- Use KQuickCharts for report charts when the module is available.
- Keep database operations behind a repository API.
- Avoid the preliminary QML `SortFilterProxyModel` API as a version 1 dependency.

## 12. Product analytics and success measures

Version 1 contains no telemetry. Success must be evaluated locally through product behavior and user feedback.

Initial success criteria:

- The user can capture and categorize a new task in less than 20 seconds.
- The user can start or switch tracked work in no more than two actions.
- The weekly report total matches the sum of its daily totals.
- Restarting Plasma during an active session does not lose or duplicate time.
- Every drag operation remains correct after a status filter is applied or cleared.
- The widget remains usable at its documented minimum desktop size.

## 13. Release plan

### Phase 1: Interface prototype

- Create the Plasma package and metadata.
- Build the full desktop representation.
- Render categories and task cards from sample data.
- Implement details navigation and responsive sizing.
- Implement drag interaction without persistence.

### Phase 2: Persistent task management

- Add database initialization and migrations.
- Add category and task operations.
- Persist task ordering and cross-category moves.
- Add status events and status filters.

### Phase 3: Time tracking

- Add the single-active-session invariant.
- Add start, pause, resume, and stop behavior.
- Recover active sessions after restart.
- Add manual work-session editing and validation.

### Phase 4: Reports

- Add timezone-safe interval splitting.
- Add weekly and monthly aggregation.
- Add charts and task/category breakdowns.
- Add report navigation.

### Phase 5: Quality and release

- Add unit and integration tests.
- Test desktop, panel, HiDPI, light theme, and dark theme behavior.
- Add keyboard ordering controls and accessible labels.
- Validate install, upgrade, and migration paths.
- Package the release as a `.plasmoid` archive.

## 14. Version 1 acceptance criteria

Version 1 is complete when all these statements are true:

1. The widget installs through `kpackagetool6` and appears in **Add Widgets**.
2. The widget renders its full task interface when placed on the desktop.
3. The user can create, edit, archive, and delete tasks.
4. The user can create and manage colored categories.
5. The user can filter tasks by status.
6. The user can reorder visible tasks without corrupting hidden task order.
7. The user can move a task between categories.
8. The widget enforces one active timer.
9. The widget recovers an active timer after a Plasma restart.
10. The user can correct work sessions and status history.
11. Weekly and monthly totals remain correct across midnight and reporting-period boundaries.
12. The interface remains usable with keyboard navigation and 200 percent display scaling.
13. Automated tests cover database migrations, timer transitions, ordering, filtering, and report aggregation.

## 15. Open product decisions

- Final product name and plugin identifier.
- Whether clicking Pause should retain an explicit paused state or simply close the current session.
- Whether completing a task should automatically stop its active timer.
- Whether archived categories remain visible when all contained tasks are archived.
- Whether version 1 should render Markdown in task descriptions or treat Markdown as plain text.
- Whether CSV export and database backup are required before regular daily use.

