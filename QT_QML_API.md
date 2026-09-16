# Qt 6 and QML API reference for Workbench

This document maps Workbench behavior to public Qt 6 and QML APIs.

## 1. Versionless imports

Use versionless imports for Qt 6 code:

```qml
import QtQuick
import QtQuick.Layouts
import QtQuick.LocalStorage
import QtQml.Models
```

Versionless imports allow the installed Qt 6 runtime to select the available module version. Do not copy Qt 5 import versions from older plasmoid examples.

## 2. `ListView`

`ListView` renders the card list and instantiates only enough delegates to cover the visible area.

Relevant APIs:

| API | Use |
| --- | --- |
| `model` | Provide task rows from a QML `ListModel` or a later C++ model. |
| `delegate` | Render one `TaskCard` per model row. |
| `section.property` | Group adjacent task rows by category. |
| `section.delegate` | Render `CategoryHeader` for each category group. |
| `header` | Render status filters or the create-task action if they scroll with the list. |
| `move` | Animate a task that changes position. |
| `moveDisplaced` | Animate tasks displaced by a reorder operation. |
| `reuseItems` | Reuse delegates when testing confirms that reuse improves performance. |
| `clip` | Prevent delegates from drawing outside the viewport. |

Delegate rule:

> Store task state in the model or database. Do not store task state in a delegate.

Qt can destroy or reuse delegates when they leave the visible area. An active timer, expanded state, or unsaved task change stored only in a delegate can therefore disappear or move to another task.

Reference: [`ListView` QML type](https://doc.qt.io/qt-6/qml-qtquick-listview.html)

## 3. Model roles

The task view model should expose these roles:

| Role | Type | Purpose |
| --- | --- | --- |
| `taskId` | string | Stable task identity. |
| `categoryId` | string | Stable parent-category identity. |
| `categoryName` | string | Category header text. |
| `categoryColor` | color/string | Card and category color. |
| `title` | string | Task title. |
| `detailsPreview` | string | Optional one-line description preview. |
| `status` | string | Current task status. |
| `position` | integer | Persistent task ordering value. |
| `trackedSeconds` | integer | Completed tracked time for the task. |
| `activeStartedAt` | date/string/null | Start of the active work session. |
| `archived` | boolean | Whether normal views hide the task. |

Use `taskId` and `categoryId` for commands. Do not pass a visible index to a persistent operation because filtering and grouping change visible indexes.

## 4. Filtering

### 4.1 Version 1 QML approach

The repository should query tasks that match the selected statuses and repopulate the view model. The query must preserve category and task ordering.

Example query shape:

```sql
SELECT ...
FROM tasks
JOIN categories ON categories.id = tasks.category_id
WHERE tasks.archived = 0
  AND tasks.status IN (?, ?)
ORDER BY categories.position, tasks.position, tasks.created_at_utc;
```

Avoid hiding delegates by setting only `visible: false`. Hidden delegates can retain layout space and remain instantiated.

### 4.2 Future native approach

Use `QSortFilterProxyModel` when the project adds a native C++ task model. The proxy model can filter by status and preserve a separate source model.

Do not require the QML `SortFilterProxyModel` in version 1. Qt introduced that QML type in Qt 6.10 and marks it as preliminary.

References:

- [`QSortFilterProxyModel`](https://doc.qt.io/qt-6/qsortfilterproxymodel.html)
- [QML `SortFilterProxyModel`](https://doc.qt.io/qt-6/qml-qtqml-models-sortfilterproxymodel.html)

## 5. Drag-and-drop ordering

Qt Quick supplies three relevant mechanisms:

- `DragHandler` or `MouseArea.drag` moves the dragged card.
- The attached `Drag` object generates drag events.
- `DropArea` receives the drag when the pointer crosses another card or category target.

The Qt dynamic ordering tutorial uses `DelegateModel.items.move()` to change visible order. Workbench must persist the operation through the repository instead.

Recommended command contract:

```qml
taskStore.moveTask({
    taskId: draggedTaskId,
    targetTaskId: targetTaskId,
    targetCategoryId: targetCategoryId,
    placement: "before"
})
```

The repository must calculate source positions from stable identifiers. The repository must not assume that visible model indexes match database order while a filter is active.

Recommended drag sequence:

1. Start the visual drag after the user moves the drag handle beyond a small threshold.
2. Display a placeholder at the proposed destination.
3. Call the repository once when the user releases the drag.
4. Update the database in one transaction.
5. Reload or patch the source model after the transaction succeeds.
6. Restore the previous model state and show an error if the write fails.

Keyboard alternatives must call the same repository operation.

References:

- [QML dynamic view ordering tutorial](https://doc.qt.io/qt-6/qtquick-tutorials-dynamicview-dynamicview3-example.html)
- [`Drag` attached property](https://doc.qt.io/qt-6/qml-qtquick-drag.html)
- [`DropArea` QML type](https://doc.qt.io/qt-6/qml-qtquick-droparea.html)
- [`DragHandler` QML type](https://doc.qt.io/qt-6/qml-qtquick-draghandler.html)

## 6. `QtQuick.LocalStorage`

Import:

```qml
import QtQuick.LocalStorage as Sql
```

Open the database with a product-specific identifier:

```javascript
const db = Sql.LocalStorage.openDatabaseSync(
    "com.example.workbench",
    "1.0",
    "Workbench data",
    5 * 1024 * 1024
)
```

Relevant methods:

| Method | Use |
| --- | --- |
| `openDatabaseSync()` | Open or create the product database. |
| `db.transaction(callback)` | Execute an atomic read/write transaction. |
| `db.readTransaction(callback)` | Execute a read-only transaction. |
| `db.changeVersion(from, to, callback)` | Change the database version with a migration transaction. |
| `tx.executeSql(statement, values)` | Execute parameterized SQL and read returned rows. |

Always bind user-provided values:

```javascript
tx.executeSql(
    "UPDATE tasks SET title = ?, updated_at_utc = ? WHERE id = ?",
    [title, updatedAtUtc, taskId]
)
```

Do not concatenate a title, description, category name, status, note, timestamp, or identifier into an SQL string.

Known characteristics:

- The API is synchronous.
- The underlying storage uses SQLite.
- Qt stores the database in the QML engine’s offline storage location.
- The database is user-specific but is not encrypted by this API.
- Database connections close when JavaScript garbage collection releases them.

Keep transactions short because synchronous database work blocks the QML thread.

Reference: [Qt Quick Local Storage](https://doc.qt.io/qt-6/qtquick-localstorage-qmlmodule.html)

## 7. JavaScript repository module

Place database logic in a dedicated JavaScript module, for example `contents/code/Database.js`.

Recommended repository surface:

```text
initialize()
listCategories()
createCategory(input)
updateCategory(input)
moveCategory(input)
deleteCategory(input)

listTasks(filter)
getTask(taskId)
createTask(input)
updateTask(input)
moveTask(input)
archiveTask(taskId)
deleteTask(taskId)

startTimer(taskId, timezoneId)
stopTimer(taskId, stoppedAtUtc)
listWorkSessions(taskId)
createWorkSession(input)
updateWorkSession(input)
deleteWorkSession(sessionId)

changeStatus(taskId, status, occurredAtUtc)
listStatusEvents(taskId)
updateStatusEvent(input)
deleteStatusEvent(eventId)

weeklyReport(input)
monthlyReport(input)
```

Return plain data from the repository. Keep QML controls and component references out of the repository.

## 8. Timers and clock behavior

Use the QML `Timer` only to refresh visible elapsed text:

```qml
Timer {
    interval: 1000
    repeat: true
    running: taskStore.hasActiveSession
    onTriggered: taskStore.refreshDisplayedElapsedTime()
}
```

Do not increase a stored counter on each timer tick. QML timers can pause when rendering stops, the system sleeps, or Plasma restarts.

Calculate visible elapsed time from:

```text
current UTC time - persisted active-session start time
```

Stop behavior must write an end timestamp once. A repeated stop request must not create a duplicate work session or change an already closed session.

Reference: [`Timer` QML type](https://doc.qt.io/qt-6/qml-qtqml-timer.html)

## 9. Dates and timezones

Store UTC timestamps in an ISO 8601 representation that includes the UTC designator, for example:

```text
2026-09-14T21:15:00.000Z
```

Store an IANA timezone identifier with each work session, for example:

```text
America/Mazatlan
Europe/Madrid
```

QML and JavaScript date APIs can format dates, but complex timezone-safe interval splitting is difficult to test in interface code. Isolate report date logic in `Reports.js` and cover daylight-saving transitions with tests.

If timezone behavior becomes unreliable or report requirements expand, move time calculations to C++ with `QDateTime` and `QTimeZone`.

References:

- [`QDateTime`](https://doc.qt.io/qt-6/qdatetime.html)
- [`QTimeZone`](https://doc.qt.io/qt-6/qtimezone.html)

## 10. Layouts and responsive sizing

Use Qt Quick Layouts instead of manual coordinates:

- `ColumnLayout` for the main vertical structure.
- `RowLayout` for filters and compact action groups.
- `GridLayout` for responsive report summaries.
- `Layout.fillWidth` and `Layout.fillHeight` for flexible regions.
- Explicit minimum dimensions on the full representation.

Avoid binding a child’s size to the same layout that derives its size from that child. Such loops produce binding warnings and unstable layouts.

Reference: [Qt Quick Layouts overview](https://doc.qt.io/qt-6/qtquicklayouts-index.html)

## 11. Accessibility

Use the `Accessible` attached object for custom controls and icon-only buttons:

```qml
PlasmaComponents.ToolButton {
    icon.name: "media-playback-start"
    Accessible.name: i18n("Start timer for %1", taskTitle)
}
```

Expose status and timer activity through text or accessible descriptions. Do not communicate these states only through color or animation.

Reference: [`Accessible` attached property](https://doc.qt.io/qt-6/qml-qtquick-accessible.html)

## 12. Future Qt/C++ model APIs

If the project adopts a native backend, use:

| API | Purpose |
| --- | --- |
| `QAbstractListModel` | Expose task and report rows to QML. |
| `roleNames()` | Map model role numbers to QML role names. |
| `beginInsertRows()` and `endInsertRows()` | Notify views about inserted tasks. |
| `beginMoveRows()` and `endMoveRows()` | Notify views about persistent reordering. |
| `dataChanged()` | Notify views after edits or timer state changes. |
| `QSortFilterProxyModel` | Provide status filtering without duplicating source data. |
| `QSqlDatabase` | Manage the SQLite connection. |
| `QSqlQuery` | Execute parameterized SQL. |
| `QStandardPaths` | Select a predictable application data path. |

References:

- [`QAbstractListModel`](https://doc.qt.io/qt-6/qabstractlistmodel.html)
- [`QSortFilterProxyModel`](https://doc.qt.io/qt-6/qsortfilterproxymodel.html)
- [`QSqlDatabase`](https://doc.qt.io/qt-6/qsqldatabase.html)
- [`QStandardPaths`](https://doc.qt.io/qt-6/qstandardpaths.html)

