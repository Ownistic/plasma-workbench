import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "time" as WorkbenchTime

import "../code/Database.js" as Database
import "../code/Reports.js" as Reports

Item {
    id: root

    required property var plasmoidConfiguration
    required property var plasmoidRoot
    property alias workspaces: workspaceModel
    property var selectedStatuses: []
    property alias categories: categoryModel
    property string selectedWorkspaceId: ""
    property var tasksByCategory: ({})
    property alias categoryDeleteConfirmation: categoryDeleteDialog
    property string currentPage: "board"
    property string moveError: ""
    property string draggedTaskId: ""
    property string draggedCategoryId: ""
    property string draggedTaskTargetId: ""
    property string draggedTaskTargetCategoryId: ""
    property string draggedTaskPlacement: "before"
    property var draggedTaskItem: null
    property var draggedTaskData: null
    property var draggedTaskPreviewItem: null
    property string draggedCategoryTargetId: ""
    property string draggedCategoryPlacement: "before"
    property real draggedCategoryTargetBaseHeight: 0
    property var draggedCategoryItem: null
    property var draggedCategoryData: null
    property var draggedCategoryTasks: []
    property real draggedCategoryGroupHeight: 0
    property real draggedCategoryOverlayX: 0
    property real draggedCategoryOverlayY: 0
    property var draggedCategoryPreviewItem: null
    property bool taskDropHandled: false
    property bool categoryDropHandled: false
    property string keepActiveTaskId: ""
    property var activeCategoryStartedAts: ({})
    property var categoryTotalTimes: ({})
    property var todayCategorySeconds: ({})
    property var totalTimeCategories: ({})
    property double categoryTimeSnapshotMilliseconds: 0
    property string todayLocalDate: ""
    readonly property var activeSessions: root.plasmoidRoot.activeSessions
    readonly property var activeSession: root.plasmoidRoot.activeSession
    readonly property bool hasActiveSession: root.plasmoidRoot.hasActiveSession
    readonly property string activeElapsedText: root.plasmoidRoot.activeElapsedText
    readonly property string activeTaskSummary: root.plasmoidRoot.activeTaskSummary
    readonly property string reportTimezone: WorkbenchTime.TimeMath.isValidTimeZone(root.plasmoidConfiguration.reportTimezone)
        ? root.plasmoidConfiguration.reportTimezone : WorkbenchTime.TimeMath.systemTimeZoneId()
    readonly property int firstDayOfWeek: root.plasmoidConfiguration.firstDayOfWeek >= 1
        && root.plasmoidConfiguration.firstDayOfWeek <= 7 ? root.plasmoidConfiguration.firstDayOfWeek : 1
    readonly property bool use24HourTime: root.plasmoidConfiguration.use24HourTime !== false
    readonly property int unusualSessionHours: Math.max(1, Number(root.plasmoidConfiguration.unusualSessionHours || 16))
    readonly property bool allowConcurrentTimers: root.plasmoidConfiguration.allowConcurrentTimers === true

    ListModel { id: taskModel }
    ListModel { id: workspaceModel }
    ListModel { id: categoryModel }
    ListModel { id: visibleCategoryModel }

    Timer {
        interval: 60 * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.reload()
    }

    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: {
            const localDate = WorkbenchTime.TimeMath.localDateForUtc(new Date().toISOString(), root.reportTimezone)
            if (localDate && localDate !== root.todayLocalDate) {
                root.reload()
            }
        }
    }

    Timer {
        id: moveErrorTimer
        interval: 5000
        onTriggered: root.moveError = ""
    }

    function formatSeconds(seconds) {
        return root.plasmoidRoot.formatSeconds(seconds)
    }

    function taskElapsedText(task) {
        const total = Number(task.trackedSeconds || 0)
        root.plasmoidRoot.elapsedRefresh
        return root.plasmoidRoot.formatSeconds(total + (task.activeStartedAt
            ? root.plasmoidRoot.elapsedSeconds(task.activeStartedAt) : 0))
    }

    function refreshCategoryTimes() {
        const now = new Date()
        const localParts = WorkbenchTime.TimeMath.localPartsForUtc(now.toISOString(), root.reportTimezone)
        const year = Number(localParts.year)
        const month = Number(localParts.month)
        const day = Number(localParts.day)
        if (!localParts.valid || !Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)
                || month < 1 || month > 12 || day < 1 || day > 31) {
            return
        }
        let report
        try {
            report = Reports.dailyReport(WorkbenchTime.TimeMath, {
                year: year,
                month: month,
                day: day,
                timezoneId: root.reportTimezone,
                firstDayOfWeek: root.firstDayOfWeek,
                currentUtc: now.toISOString()
            })
        } catch (error) {
            return
        }
        const todayTotals = {}
        for (let index = 0; index < report.byCategory.length; index += 1) {
            const category = report.byCategory[index]
            todayTotals[category.id] = category.seconds
        }
        const activeSessionsByCategory = {}
        const activeSessions = Database.listActiveCategorySessions()
        for (let index = 0; index < activeSessions.length; index += 1) {
            const session = activeSessions[index]
            if (!activeSessionsByCategory[session.categoryId]) {
                activeSessionsByCategory[session.categoryId] = []
            }
            activeSessionsByCategory[session.categoryId].push(session.startedAtUtc)
        }
        root.todayCategorySeconds = todayTotals
        root.activeCategoryStartedAts = activeSessionsByCategory
        root.categoryTimeSnapshotMilliseconds = now.getTime()
        root.todayLocalDate = localParts.date
        for (const categoryId in root.totalTimeCategories) {
            if (root.totalTimeCategories[categoryId]) {
                root.refreshCategoryTotal(categoryId, now)
            }
        }
    }

    function activeSecondsSinceSnapshot(startedAts, snapshotMilliseconds) {
        let earliestStart = Date.now()
        for (let index = 0; index < startedAts.length; index += 1) {
            earliestStart = Math.min(earliestStart,
                Math.max(Date.parse(startedAts[index]), snapshotMilliseconds))
        }
        return Math.max(0, (Date.now() - earliestStart) / 1000)
    }

    function refreshCategoryTotal(categoryId, now) {
        const snapshot = now || new Date()
        const total = Database.categoryTimeTotal(categoryId, snapshot.toISOString())
        total.snapshotMilliseconds = snapshot.getTime()
        const totals = {}
        for (const visibleCategoryId in root.categoryTotalTimes) {
            totals[visibleCategoryId] = root.categoryTotalTimes[visibleCategoryId]
        }
        totals[categoryId] = total
        root.categoryTotalTimes = totals
    }

    function categoryTodaySeconds(categoryId) {
        root.plasmoidRoot.elapsedRefresh
        let seconds = Number(root.todayCategorySeconds[categoryId] || 0)
        return seconds + root.activeSecondsSinceSnapshot(root.activeCategoryStartedAts[categoryId] || [],
            root.categoryTimeSnapshotMilliseconds)
    }

    function categoryTotalSeconds(categoryId) {
        root.plasmoidRoot.elapsedRefresh
        const total = root.categoryTotalTimes[categoryId]
        if (!total) {
            return 0
        }
        let seconds = Number(total.trackedSeconds || 0)
        return seconds + root.activeSecondsSinceSnapshot(total.activeStartedAts, total.snapshotMilliseconds)
    }

    function categoryTimeText(categoryId) {
        const showTotal = root.totalTimeCategories[categoryId] === true
        const seconds = showTotal ? root.categoryTotalSeconds(categoryId) : root.categoryTodaySeconds(categoryId)
        return showTotal ? i18n("Total: %1", root.formatSeconds(seconds))
            : i18n("Today: %1", root.formatSeconds(seconds))
    }

    function toggleCategoryTimeDisplay(categoryId) {
        const visibleTotals = {}
        for (const visibleCategoryId in root.totalTimeCategories) {
            visibleTotals[visibleCategoryId] = root.totalTimeCategories[visibleCategoryId]
        }
        visibleTotals[categoryId] = visibleTotals[categoryId] !== true
        root.totalTimeCategories = visibleTotals
        if (visibleTotals[categoryId]) {
            root.refreshCategoryTotal(categoryId)
        }
    }

    function formatTimestamp(utc) {
        const formatted = WorkbenchTime.TimeMath.formatUtcForLocal(utc, root.reportTimezone, root.use24HourTime)
        return formatted.valid ? formatted.formatted : utc
    }

    function currentLocalDate() {
        const local = WorkbenchTime.TimeMath.localPartsForUtc(new Date().toISOString(), root.reportTimezone)
        return local.valid ? local.date : ""
    }

    function openDailyTimeline(categoryId, taskId, date) {
        reportsPage.openDailyReport(categoryId || "", taskId || "", date || "")
        root.currentPage = "reports"
    }

    function reloadWorkspace() {
        const tasks = Database.listTasks({
            statuses: root.selectedStatuses,
            showArchived: root.plasmoidConfiguration.showArchivedTasks,
            workspaceId: root.selectedWorkspaceId
        })
        const categories = Database.listCategories(root.selectedWorkspaceId)
        const groupedTasks = {}
        for (let taskIndex = 0; taskIndex < tasks.length; taskIndex += 1) {
            const task = tasks[taskIndex]
            if (!groupedTasks[task.categoryId]) {
                groupedTasks[task.categoryId] = []
            }
            groupedTasks[task.categoryId].push(task)
        }
        root.tasksByCategory = groupedTasks
        taskModel.clear()
        categoryModel.clear()
        visibleCategoryModel.clear()
        for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex += 1) {
            categoryModel.append(categories[categoryIndex])
            visibleCategoryModel.append(categories[categoryIndex])
        }
        for (let taskIndex = 0; taskIndex < tasks.length; taskIndex += 1) {
            taskModel.append(tasks[taskIndex])
        }
    }

    function reload() {
        const workspaces = Database.listWorkspaces()
        workspaceModel.clear()
        for (let workspaceIndex = 0; workspaceIndex < workspaces.length; workspaceIndex += 1) {
            workspaceModel.append(workspaces[workspaceIndex])
        }
        if (!root.selectedWorkspaceId || root.workspaceIndex(root.selectedWorkspaceId) < 0) {
            root.selectedWorkspaceId = workspaces.length > 0 ? workspaces[0].id : ""
        }
        root.reloadWorkspace()
        root.refreshCategoryTimes()
        root.plasmoidRoot.activeSessions = Database.getActiveSessions()
        if (!root.allowConcurrentTimers && root.activeSessions.length > 1 && !concurrentTimerResolutionDialog.visible) {
            root.keepActiveTaskId = root.activeSessions[0].task_id
            concurrentTimerResolutionDialog.open()
        }
    }

    function workspaceIndex(workspaceId) {
        for (let index = 0; index < workspaceModel.count; index += 1) {
            if (workspaceModel.get(index).id === workspaceId) {
                return index
            }
        }
        return -1
    }

    function selectWorkspace(workspaceId) {
        if (workspaceId && workspaceId !== root.selectedWorkspaceId) {
            root.selectedWorkspaceId = workspaceId
            root.reloadWorkspace()
        }
    }

    function toggleStatus(status) {
        const statuses = root.selectedStatuses.slice()
        const index = statuses.indexOf(status)
        if (index === -1) {
            statuses.push(status)
        } else {
            statuses.splice(index, 1)
        }
        root.selectedStatuses = statuses
        root.reload()
    }

    function toggleTimer(task) {
        if (root.plasmoidRoot.isTaskActive(task.taskId)) {
            Database.stopTimer(task.taskId)
        } else {
            Database.startTimer(task.taskId, root.reportTimezone, undefined, root.allowConcurrentTimers)
        }
        root.reload()
    }

    function isTaskActive(taskId) {
        return root.plasmoidRoot.isTaskActive(taskId)
    }

    function openSettings() {
        root.currentPage = "settings"
    }

    function closeSettings() {
        root.currentPage = "board"
    }

    function openReports(showMonthly) {
        reportsPage.openReport(showMonthly)
        root.currentPage = "reports"
    }

    function closeReports() {
        reportsPage.clearReport()
        root.currentPage = "board"
    }

    function requestConcurrentTimersChange(enabled) {
        if (enabled) {
            root.plasmoidConfiguration.allowConcurrentTimers = true
            root.reload()
            return
        }
        if (root.activeSessions.length <= 1) {
            root.plasmoidConfiguration.allowConcurrentTimers = false
            root.reload()
            return
        }
        root.keepActiveTaskId = root.activeSessions[0].task_id
        concurrentTimerResolutionDialog.open()
    }

    function resolveConcurrentTimerConflict() {
        try {
            Database.stopTimersExcept(root.keepActiveTaskId)
            root.plasmoidConfiguration.allowConcurrentTimers = false
            concurrentTimerResolutionDialog.close()
            root.reload()
        } catch (error) {
            root.moveError = error.message
            moveErrorTimer.restart()
            root.reload()
            if (root.activeSessions.length <= 1) {
                concurrentTimerResolutionDialog.close()
            } else {
                root.keepActiveTaskId = root.activeSessions[0].task_id
            }
        }
    }

    function cancelConcurrentTimerResolution() {
        root.plasmoidConfiguration.allowConcurrentTimers = true
        concurrentTimerResolutionDialog.close()
        root.reload()
    }

    function isActiveTimerSelection(taskId) {
        return root.activeSessions.some(function(session) { return session.task_id === taskId })
    }

    onAllowConcurrentTimersChanged: {
        if (!root.allowConcurrentTimers && root.activeSessions.length > 1 && !concurrentTimerResolutionDialog.visible) {
            root.keepActiveTaskId = root.activeSessions[0].task_id
            concurrentTimerResolutionDialog.open()
        }
    }

    function adjacentTask(task, direction) {
        if (taskModel.count === 0) {
            return null
        }
        let currentIndex = -1
        for (let index = 0; index < taskModel.count; index += 1) {
            const candidate = taskModel.get(index)
            if (candidate.categoryId === task.categoryId && candidate.taskId === task.taskId) {
                currentIndex = index
                break
            }
        }
        for (let index = currentIndex + direction; index >= 0 && index < taskModel.count; index += direction) {
            const candidate = taskModel.get(index)
            if (candidate.categoryId === task.categoryId) {
                return candidate
            }
        }
        return null
    }

    function isVisibleCategory(categoryId) {
        for (let index = 0; index < visibleCategoryModel.count; index += 1) {
            if (visibleCategoryModel.get(index).id === categoryId) {
                return true
            }
        }
        return false
    }

    function moveTask(task, targetTask, placement) {
        if (!targetTask) {
            return
        }
        try {
            Database.moveTask({
                taskId: task.taskId,
                targetCategoryId: targetTask.categoryId,
                targetTaskId: targetTask.taskId,
                placement: placement
            })
            root.moveError = ""
        } catch (error) {
            root.moveError = error.message
            moveErrorTimer.restart()
        } finally {
            root.reload()
        }
    }

    function moveTaskById(taskId, targetTaskId, targetCategoryId, placement) {
        try {
            Database.moveTask({
                taskId: taskId,
                targetCategoryId: targetCategoryId,
                targetTaskId: targetTaskId || null,
                placement: placement || "before"
            })
            root.moveError = ""
        } catch (error) {
            root.moveError = error.message
            moveErrorTimer.restart()
        } finally {
            root.reload()
        }
    }

    function moveCategory(categoryId, targetCategoryId, placement) {
        try {
            Database.moveCategory({
                categoryId: categoryId,
                targetCategoryId: targetCategoryId,
                placement: placement
            })
            root.moveError = ""
        } catch (error) {
            root.moveError = error.message
            moveErrorTimer.restart()
        } finally {
            root.reload()
        }
    }

    function beginTaskDrag(task, dragItem) {
        root.draggedTaskId = task.taskId
        root.draggedTaskItem = dragItem
        root.draggedTaskData = task
        root.taskDropHandled = false
        root.draggedTaskTargetId = ""
        root.draggedTaskTargetCategoryId = task.categoryId
        root.draggedTaskPlacement = "before"
        root.draggedTaskPreviewItem = null
        root.moveError = ""
    }

    function previewTaskMove(sourceTaskId, targetTaskId, targetCategoryId, placement, previewItem) {
        if (sourceTaskId !== root.draggedTaskId || sourceTaskId === targetTaskId) {
            return
        }
        root.draggedTaskTargetId = targetTaskId || ""
        root.draggedTaskTargetCategoryId = targetCategoryId
        root.draggedTaskPlacement = placement
        root.draggedTaskPreviewItem = previewItem || null
    }

    function commitTaskDrop(sourceTaskId, targetTaskId, targetCategoryId, placement) {
        root.taskDropHandled = true
        try {
            Database.moveTask({
                taskId: sourceTaskId,
                targetCategoryId: targetCategoryId,
                targetTaskId: targetTaskId || null,
                placement: placement
            })
            root.moveError = ""
        } catch (error) {
            root.moveError = error.message
            moveErrorTimer.restart()
        }
    }

    function finishTaskDrag() {
        root.draggedTaskId = ""
        root.draggedTaskTargetId = ""
        root.draggedTaskTargetCategoryId = ""
        root.draggedTaskItem = null
        root.draggedTaskData = null
        root.draggedTaskPreviewItem = null
        root.taskDropHandled = false
        root.reload()
    }

    function beginCategoryDrag(category, dragItem, dragGroup) {
        const group = dragGroup || dragItem
        const groupHeight = Math.max(
            Number(group.height || 0),
            Number(group.implicitHeight || 0),
            Number(group.childrenRect ? group.childrenRect.height : 0),
            Kirigami.Units.gridUnit * 2
        )
        const tasks = []
        for (let index = 0; index < taskModel.count; index += 1) {
            const task = taskModel.get(index)
            if (task.categoryId === category.id && task.categoryCollapsed === 0) {
                tasks.push(task)
            }
        }
        root.draggedCategoryItem = dragItem
        root.draggedCategoryData = category
        root.draggedCategoryTasks = tasks
        root.draggedCategoryGroupHeight = groupHeight
        root.draggedCategoryId = category.id
        root.categoryDropHandled = false
        root.draggedCategoryTargetId = ""
        root.draggedCategoryPlacement = "before"
        root.draggedCategoryTargetBaseHeight = 0
        root.draggedCategoryPreviewItem = null
        root.moveError = ""
        root.updateCategoryDragPosition(dragItem)
    }

    function updateCategoryDragPosition(dragItem) {
        if (!dragItem) {
            return
        }
        const position = dragItem.mapToItem(root, 0, 0)
        root.draggedCategoryOverlayX = position.x
        root.draggedCategoryOverlayY = position.y
    }

    function previewCategoryMove(sourceCategoryId, targetCategoryId, placement, previewItem) {
        const sourceId = sourceCategoryId ? String(sourceCategoryId) : ""
        const targetId = targetCategoryId ? String(targetCategoryId) : ""
        if (sourceId !== root.draggedCategoryId) {
            return
        }
        if (sourceId === targetId) {
            return
        }
        root.draggedCategoryTargetId = targetId
        root.draggedCategoryPlacement = placement
        root.draggedCategoryPreviewItem = previewItem || null
    }

    function categoryGroupPlacement(dragY, targetHeight, targetCategoryId) {
        const targetId = targetCategoryId ? String(targetCategoryId) : ""
        if (root.draggedCategoryTargetId !== targetId || root.draggedCategoryTargetBaseHeight <= 0) {
            root.draggedCategoryTargetBaseHeight = targetHeight
        }
        return dragY >= root.draggedCategoryTargetBaseHeight / 2 ? "after" : "before"
    }

    function commitCategoryDrop(sourceCategoryId, targetCategoryId, placement) {
        const sourceId = sourceCategoryId ? String(sourceCategoryId) : ""
        const targetId = targetCategoryId ? String(targetCategoryId) : ""
        root.categoryDropHandled = true
        try {
            Database.moveCategory({
                categoryId: sourceId,
                targetCategoryId: targetId || null,
                placement: placement
            })
            root.moveError = ""
        } catch (error) {
            root.moveError = error.message
            moveErrorTimer.restart()
        }
    }

    function finishCategoryDrag() {
        root.draggedCategoryId = ""
        root.draggedCategoryTargetId = ""
        root.draggedCategoryTargetBaseHeight = 0
        root.draggedCategoryItem = null
        root.draggedCategoryData = null
        root.draggedCategoryTasks = []
        root.draggedCategoryGroupHeight = 0
        root.draggedCategoryOverlayX = 0
        root.draggedCategoryOverlayY = 0
        root.draggedCategoryPreviewItem = null
        root.categoryDropHandled = false
        root.reload()
    }

    function openTask(taskId) {
        detailsDialog.loadTask(taskId)
        if (detailsDialog.task) {
            root.currentPage = "details"
        }
    }

    function closeTaskDetails() {
        detailsDialog.visible = false
        root.currentPage = "board"
        taskList.forceActiveFocus()
    }

    function requestTaskDetailsClose() {
        if (detailsDialog.hasUnsavedChanges) {
            discardTaskChangesDialog.open()
            return
        }
        root.closeTaskDetails()
    }

    Component.onCompleted: {
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkbenchTime.TimeMath.isValidTimeZone(timezoneId)
        })
        Database.initialize()
        const configuredStatuses = root.plasmoidConfiguration.defaultStatusFilter.split(",")
        root.selectedStatuses = configuredStatuses.filter(function(status) {
            return ["backlog", "ready", "in_progress", "blocked", "completed"].indexOf(status) !== -1
        })
        root.reload()
    }

    ColumnLayout {
        id: boardContent
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        visible: root.currentPage === "board"

        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 2
                text: i18n("Workbench")
            }

            PlasmaComponents.Label {
                id: activeTimeDisplay
                objectName: "daily-timeline-header"
                text: root.hasActiveSession
                    ? (root.activeSessions.length === 1 ? root.activeElapsedText
                        : i18np("%1 timer", "%1 timers", root.activeSessions.length))
                    : i18n("No timer")
                Accessible.name: root.activeTaskSummary

                TapHandler {
                    onTapped: root.openDailyTimeline()
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "list-add"
                Accessible.name: i18n("Create task")
                onClicked: createTaskDialog.open()
            }

            PlasmaComponents.ToolButton {
                icon.name: "folder-new"
                Accessible.name: i18n("Create category")
                onClicked: createCategoryDialog.open()
            }

            PlasmaComponents.ToolButton {
                icon.name: "user-trash"
                Accessible.name: i18n("Manage category trash")
                onClicked: categoryTrashDialog.openTrash()
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-list-details"
                Accessible.name: i18n("Manage categories")
                onClicked: categoryManagementDialog.open()
            }

            PlasmaComponents.ToolButton {
                icon.name: "office-chart-bar"
                Accessible.name: i18n("Open reports")
                onClicked: root.openReports(false)
            }

            PlasmaComponents.ToolButton {
                objectName: "settings-button"
                icon.name: "configure"
                Accessible.name: i18n("Open settings")
                onClicked: root.openSettings()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Math.min(boardContent.width - createWorkspaceButton.implicitWidth
                    - Kirigami.Units.smallSpacing, Math.max(Kirigami.Units.gridUnit * 16,
                    workspaceModel.count * Kirigami.Units.gridUnit * 8))
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.25
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.18)
                border.width: 1
                radius: Kirigami.Units.smallSpacing

                Row {
                    id: workspaceTabs
                    objectName: "workspace-tabs"
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 3

                    Repeater {
                        model: workspaceModel

                        Controls.AbstractButton {
                            id: workspaceTab
                            required property var model
                            readonly property bool workspaceSelected: root.selectedWorkspaceId === model.id
                            objectName: "workspace-tab-" + model.id
                            width: (workspaceTabs.width
                                - workspaceTabs.spacing * Math.max(0, workspaceModel.count - 1))
                                / Math.max(1, workspaceModel.count)
                            height: workspaceTabs.height
                            hoverEnabled: true
                            leftInset: 0
                            rightInset: 0
                            topInset: 0
                            bottomInset: 0
                            padding: Kirigami.Units.smallSpacing
                            Accessible.name: i18n("Open %1 workspace", model.name)
                            Accessible.role: Accessible.PageTab
                            onClicked: root.selectWorkspace(model.id)

                            background: Rectangle {
                                radius: Math.max(2, Kirigami.Units.smallSpacing - 2)
                                color: workspaceTab.workspaceSelected
                                    ? Kirigami.Theme.highlightColor
                                    : workspaceTab.hovered
                                        ? Qt.alpha(Kirigami.Theme.textColor, 0.08) : "transparent"
                                border.color: workspaceTab.workspaceSelected
                                    ? Kirigami.Theme.highlightColor : "transparent"
                                border.width: 1
                            }

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    source: model.name.toLowerCase() === "personal"
                                        ? "user-home" : model.name.toLowerCase().indexOf("4leaf") !== -1
                                            ? "office-building" : "view-grid"
                                    color: workspaceTab.workspaceSelected
                                        ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: model.name
                                    font.bold: workspaceTab.workspaceSelected
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    color: workspaceTab.workspaceSelected
                                        ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: createWorkspaceButton
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.25
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.25
                icon.name: "tab-new"
                Accessible.name: i18n("Create workspace")
                onClicked: createWorkspaceDialog.open()

                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing
                    color: createWorkspaceButton.hovered
                        ? Qt.alpha(Kirigami.Theme.highlightColor, 0.18)
                        : Kirigami.Theme.alternateBackgroundColor
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.18)
                    border.width: 1
                }
            }

            Item { Layout.fillWidth: true }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: ["backlog", "ready", "in_progress", "blocked", "completed"]

                delegate: PlasmaComponents.Button {
                    required property string modelData
                    text: modelData.replace("_", " ")
                    checkable: true
                    checked: root.selectedStatuses.indexOf(modelData) !== -1
                    Accessible.name: i18n("Filter by %1", modelData.replace("_", " "))
                    onClicked: root.toggleStatus(modelData)
                }
            }

            PlasmaComponents.Button {
                text: i18n("Clear filters")
                enabled: root.selectedStatuses.length > 0
                onClicked: {
                    root.selectedStatuses = []
                    root.reload()
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.moveError.length > 0
            text: root.moveError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Accessible.name: text
        }

        PlasmaExtras.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: categoryModel.count === 0
            text: i18n("No categories yet")
            helpfulAction: Controls.Action {
                text: i18n("Create category")
                onTriggered: createCategoryDialog.open()
            }
        }

        Flickable {
            id: taskList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: categoryModel.count > 0
            clip: true
            contentWidth: width
            contentHeight: categoryColumn.implicitHeight

            Column {
                id: categoryColumn
                width: taskList.width
                spacing: Kirigami.Units.largeSpacing

                PlasmaExtras.PlaceholderMessage {
                    width: parent.width
                    visible: taskModel.count === 0
                    text: i18n("No tasks match these filters")
                }

                Repeater {
                    model: visibleCategoryModel

                    delegate: Column {
                        id: categorySlot
                        objectName: "category-slot-" + model.id
                        required property var model
                        readonly property string currentCategoryId: model.id
                        readonly property bool draggingSource: root.draggedCategoryId === currentCategoryId
                        readonly property bool insertionTarget: root.draggedCategoryPreviewItem === categorySlot
                        readonly property real groupPlaceholderHeight: insertionTarget
                            ? (root.draggedCategoryGroupHeight || implicitHeight) : 0
                        width: categoryColumn.width
                        height: draggingSource ? 0 : implicitHeight
                        clip: true
                        spacing: Kirigami.Units.smallSpacing

                            Item {
                            id: categoryHeaderSlot
                            objectName: "category-placeholder-before-" + model.id
                            width: parent.width
                            z: root.draggedCategoryId.length > 0 ? 10 : 0
                            readonly property bool insertionTarget: categorySlot.insertionTarget && root.draggedCategoryPlacement === "before"
                            readonly property real placeholderHeight: insertionTarget
                                ? categorySlot.groupPlaceholderHeight : 0
                            height: categoryHeader.implicitHeight + placeholderHeight

                            CategoryDragGroup {
                                width: parent.width
                                height: categoryHeaderSlot.placeholderHeight
                                visible: categoryHeaderSlot.insertionTarget
                                opacity: 0.55
                                category: root.draggedCategoryData
                                tasks: root.draggedCategoryTasks
                                timeText: root.categoryTimeText(root.draggedCategoryId)
                                showingTotalTime: root.totalTimeCategories[root.draggedCategoryId] === true
                                isTaskActive: function(taskId) { return root.isTaskActive(taskId) }
                                taskElapsedText: function(task) { return root.taskElapsedText(task) }
                                objectNamePrefix: "category-drag-placeholder-before-" + model.id
                                accessibleName: categoryHeaderSlot.insertionTarget
                                    ? i18n("Category drag insertion preview") : ""
                            }

                            DropArea {
                                width: parent.width
                                height: categoryHeaderSlot.placeholderHeight
                                visible: categoryHeaderSlot.insertionTarget
                                z: 3
                                keys: ["application/x-workbench-category"]
                                onEntered: function(drag) {
                                    if (drag.source && drag.source.categoryId && drag.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.previewCategoryMove(drag.source.categoryId, categorySlot.currentCategoryId, "before", categorySlot)
                                    }
                                }
                                onDropped: function(drop) {
                                    if (drop.source && drop.source.categoryId && drop.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.commitCategoryDrop(drop.source.categoryId, categorySlot.currentCategoryId, "before")
                                        drop.acceptProposedAction()
                                    }
                                }
                            }

                            DropArea {
                                id: categoryGroupDrop
                                objectName: "category-drop-target-" + model.id
                                width: categorySlot.width
                                height: categorySlot.implicitHeight
                                y: -categoryHeaderSlot.y
                                visible: root.draggedCategoryId.length > 0 && root.draggedCategoryId !== categorySlot.currentCategoryId
                                z: 2
                                keys: ["application/x-workbench-category"]
                                onEntered: function(drag) {
                                    if (drag.source && drag.source.categoryId && drag.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.previewCategoryMove(drag.source.categoryId, categorySlot.currentCategoryId,
                                            root.categoryGroupPlacement(drag.y, height, categorySlot.currentCategoryId), categorySlot)
                                    }
                                }
                                onPositionChanged: function(drag) {
                                    if (drag.source && drag.source.categoryId && drag.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.previewCategoryMove(drag.source.categoryId, categorySlot.currentCategoryId,
                                            root.categoryGroupPlacement(drag.y, height, categorySlot.currentCategoryId), categorySlot)
                                    }
                                }
                                onDropped: function(drop) {
                                    if (drop.source && drop.source.categoryId && drop.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.commitCategoryDrop(drop.source.categoryId, categorySlot.currentCategoryId,
                                            root.draggedCategoryPlacement)
                                        drop.acceptProposedAction()
                                    }
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 2
                                y: categoryHeaderSlot.placeholderHeight - height
                                visible: root.draggedCategoryTargetId === categorySlot.currentCategoryId
                                    && root.draggedCategoryPlacement === "before"
                                color: Kirigami.Theme.highlightColor
                            }

                            CategoryHeader {
                                id: categoryHeader
                                width: parent.width
                                dragGroup: categorySlot
                                y: categoryHeaderSlot.insertionTarget && root.draggedCategoryPlacement === "before"
                                    ? categoryHeaderSlot.placeholderHeight : 0
                                z: dragging ? 2 : 1
                                categoryId: model.id
                                categoryName: model.name
                                categoryColor: model.color
                                collapsed: model.collapsed !== 0
                                timeText: root.categoryTimeText(model.id)
                                showingTotalTime: root.totalTimeCategories[model.id] === true
                                onTimeDisplayToggleRequested: root.toggleCategoryTimeDisplay(model.id)
                                onDailyTimelineRequested: root.openDailyTimeline(model.id)
                                onCollapseRequested: {
                                    Database.updateCategory({ id: model.id, collapsed: model.collapsed === 0 })
                                    root.reload()
                                }
                                onEditRequested: categoryEditorDialog.openForCategory(model)
                                onDeleteRequested: categoryDeleteDialog.openForCategory(model)
                                onDragStarted: function(dragItem, dragGroup) {
                                    root.beginCategoryDrag(model, dragItem, dragGroup)
                                }
                                onDragPositionChanged: function(dragItem) {
                                    root.updateCategoryDragPosition(dragItem)
                                }
                                onDragPreviewRequested: function(sourceCategoryId, placement, targetItem) {
                                    root.previewCategoryMove(sourceCategoryId, categorySlot.currentCategoryId, placement, targetItem)
                                }
                                onDragFinished: root.finishCategoryDrag()
                                onTaskPreviewRequested: function(taskId, targetItem) {
                                    root.previewTaskMove(taskId, null, model.id, "after", targetItem)
                                }
                                onTaskDropped: function(taskId) {
                                    root.commitTaskDrop(taskId, null, model.id, "after")
                                }
                                onCategoryDropped: function(categoryId, placement) {
                                        root.commitCategoryDrop(categoryId, categorySlot.currentCategoryId, root.draggedCategoryPlacement)
                                }
                            }

                        }

                        Repeater {
                            model: root.tasksByCategory[categorySlot.currentCategoryId] || []

                            delegate: Item {
                                id: taskSlot
                                required property var modelData
                                width: parent.width
                                opacity: categorySlot.draggingSource ? 0 : 1
                                readonly property bool shown: modelData.categoryCollapsed === 0
                                readonly property bool insertionTarget: root.draggedTaskPreviewItem === taskSlot
                                readonly property real placeholderHeight: insertionTarget
                                    ? (root.draggedTaskItem ? root.draggedTaskItem.implicitHeight : taskCard.implicitHeight) : 0
                                height: shown && !taskCard.dragging ? taskCard.implicitHeight + placeholderHeight : 0

                                Rectangle {
                                    width: parent.width
                                    height: taskSlot.placeholderHeight
                                    y: root.draggedTaskPlacement === "before" ? 0 : taskCard.implicitHeight
                                    visible: taskSlot.insertionTarget
                                    color: Kirigami.Theme.alternateBackgroundColor
                                    opacity: 0.45
                                    radius: Kirigami.Units.smallSpacing

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Kirigami.Units.largeSpacing
                                        anchors.rightMargin: Kirigami.Units.largeSpacing

                                        Rectangle {
                                            Layout.fillHeight: true
                                            Layout.preferredWidth: Kirigami.Units.smallSpacing
                                            color: root.draggedTaskData ? root.draggedTaskData.categoryColor : modelData.categoryColor
                                            radius: width / 2
                                        }

                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            text: root.draggedTaskData ? root.draggedTaskData.title : modelData.title
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                DropArea {
                                    width: parent.width
                                    height: taskSlot.placeholderHeight
                                    y: root.draggedTaskPlacement === "before" ? 0 : taskCard.implicitHeight
                                    visible: taskSlot.insertionTarget
                                    z: 3
                            keys: ["application/x-workbench-task"]
                                    onEntered: function(drag) {
                                        if (drag.source && drag.source.task && drag.source.task.taskId !== modelData.taskId) {
                                            root.previewTaskMove(drag.source.task.taskId, modelData.taskId, modelData.categoryId, root.draggedTaskPlacement, taskSlot)
                                        }
                                    }
                                    onDropped: function(drop) {
                                        if (drop.source && drop.source.task && drop.source.task.taskId !== modelData.taskId) {
                                            root.commitTaskDrop(drop.source.task.taskId, modelData.taskId, modelData.categoryId, root.draggedTaskPlacement)
                                            drop.acceptProposedAction()
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 2
                                    y: root.draggedTaskPlacement === "after" ? parent.height - height : 0
                                    visible: root.draggedTaskTargetId === modelData.taskId
                                    color: Kirigami.Theme.highlightColor
                                }

                                TaskCard {
                                    id: taskCard
                                    width: parent.width
                                    visible: taskSlot.shown || dragging
                                    y: taskSlot.insertionTarget && root.draggedTaskPlacement === "before"
                                        ? taskSlot.placeholderHeight : 0
                                    z: dragging ? 2 : 1
                                    opacity: dragging ? 0 : 1
                                    task: modelData
                                    active: root.isTaskActive(modelData.taskId)
                                    elapsedText: root.taskElapsedText(modelData)
                                    canMoveUp: root.adjacentTask(modelData, -1) !== null
                                    canMoveDown: root.adjacentTask(modelData, 1) !== null
                                    onTimerRequested: root.toggleTimer(modelData)
                                    onOpenRequested: root.openTask(modelData.taskId)
                                    onMoveUpRequested: root.moveTask(modelData, root.adjacentTask(modelData, -1), "before")
                                    onMoveDownRequested: root.moveTask(modelData, root.adjacentTask(modelData, 1), "after")
                                    onMoveToCategoryRequested: moveTaskDialog.openForTask(modelData)
                                    onDragStarted: function(dragItem) {
                                        root.beginTaskDrag(modelData, dragItem)
                                    }
                                    onDragPreviewRequested: function(sourceTaskId, placement, targetItem) {
                                        root.previewTaskMove(sourceTaskId, modelData.taskId, modelData.categoryId, placement, targetItem)
                                    }
                                    onDragFinished: root.finishTaskDrag()
                                    onDropRequested: function(sourceTaskId, placement) {
                                        root.commitTaskDrop(sourceTaskId, modelData.taskId, modelData.categoryId, placement)
                                    }
                                }
                            }
                        }

                        Item {
                            id: bottomCategoryPlaceholder
                            objectName: "category-placeholder-after-" + model.id
                            readonly property bool insertionTarget: categorySlot.insertionTarget && root.draggedCategoryPlacement === "after"
                            width: parent.width
                            height: insertionTarget ? categorySlot.groupPlaceholderHeight : 0

                            CategoryDragGroup {
                                width: parent.width
                                height: parent.height
                                visible: bottomCategoryPlaceholder.insertionTarget
                                opacity: 0.55
                                category: root.draggedCategoryData
                                tasks: root.draggedCategoryTasks
                                timeText: root.categoryTimeText(root.draggedCategoryId)
                                showingTotalTime: root.totalTimeCategories[root.draggedCategoryId] === true
                                isTaskActive: function(taskId) { return root.isTaskActive(taskId) }
                                taskElapsedText: function(task) { return root.taskElapsedText(task) }
                                objectNamePrefix: "category-drag-placeholder-after-" + model.id
                                accessibleName: bottomCategoryPlaceholder.insertionTarget
                                    ? i18n("Category drag insertion preview") : ""
                            }

                            DropArea {
                                anchors.fill: parent
                                visible: bottomCategoryPlaceholder.insertionTarget
                                z: 3
                                keys: ["application/x-workbench-category"]
                                onEntered: function(drag) {
                                    if (drag.source && drag.source.categoryId && drag.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.previewCategoryMove(drag.source.categoryId, categorySlot.currentCategoryId, "after", categorySlot)
                                    }
                                }
                                onDropped: function(drop) {
                                    if (drop.source && drop.source.categoryId && drop.source.categoryId !== categorySlot.currentCategoryId) {
                                        root.commitCategoryDrop(drop.source.categoryId, categorySlot.currentCategoryId, "after")
                                        drop.acceptProposedAction()
                                    }
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 2
                                y: parent.height - height
                                visible: bottomCategoryPlaceholder.insertionTarget
                                color: Kirigami.Theme.highlightColor
                            }
                        }

                    }
                }

                Repeater {
                    model: categoryModel

                    delegate: DropArea {
                        id: hiddenCategoryDrop
                        required property var model
                        readonly property string destinationCategoryId: String(model.id)
                        readonly property bool hiddenDestination: !root.isVisibleCategory(model.id)
                        width: parent.width
                        height: hiddenDestination && (root.draggedTaskId.length > 0 || root.draggedCategoryId.length > 0)
                            ? (root.draggedTaskItem ? root.draggedTaskItem.implicitHeight
                                : (root.draggedCategoryGroupHeight || Kirigami.Units.gridUnit * 2)) : 0
                        keys: ["application/x-workbench-task", "application/x-workbench-category"]
                        onEntered: function(drag) {
                            if (drag.source && drag.source.task) {
                                root.previewTaskMove(drag.source.task.taskId, null, model.id, "after", hiddenCategoryDrop)
                            } else if (drag.source && drag.source.categoryId && drag.source.categoryId !== hiddenCategoryDrop.destinationCategoryId) {
                                root.previewCategoryMove(drag.source.categoryId, hiddenCategoryDrop.destinationCategoryId, "after", hiddenCategoryDrop)
                            }
                        }
                        onDropped: function(drop) {
                            if (drop.source && drop.source.task) {
                                root.commitTaskDrop(drop.source.task.taskId, null, model.id, "after")
                                drop.acceptProposedAction()
                            } else if (drop.source && drop.source.categoryId && drop.source.categoryId !== hiddenCategoryDrop.destinationCategoryId) {
                                root.commitCategoryDrop(drop.source.categoryId, hiddenCategoryDrop.destinationCategoryId, "after")
                                drop.acceptProposedAction()
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Kirigami.Theme.alternateBackgroundColor
                            border.color: Kirigami.Theme.highlightColor
                            border.width: 1
                            radius: Kirigami.Units.smallSpacing
                            opacity: parent.containsDrag ? 0.7 : 0.45

                            PlasmaComponents.Label {
                                anchors.centerIn: parent
                                text: i18n("Move to %1", model.name)
                            }
                        }
                    }
                }

            }
        }
    }

    Item {
        id: dragOverlay
        objectName: "drag-overlay"
        readonly property var sourceItem: root.draggedTaskItem || root.draggedCategoryItem
        readonly property bool draggingTask: root.draggedTaskItem !== null
        readonly property bool active: draggingTask ? sourceItem !== null : root.draggedCategoryId.length > 0
        z: 100
        visible: active
        width: sourceItem ? sourceItem.width : 0
        height: draggingTask ? (sourceItem ? sourceItem.height : 0) : root.draggedCategoryGroupHeight
        x: {
            if (!sourceItem) {
                return 0
            }
            if (!dragOverlay.draggingTask) {
                return root.draggedCategoryOverlayX
            }
            sourceItem.x
            sourceItem.y
            return sourceItem.mapToItem(root, 0, 0).x
        }
        y: {
            if (!sourceItem) {
                return 0
            }
            if (!dragOverlay.draggingTask) {
                return root.draggedCategoryOverlayY
            }
            sourceItem.x
            sourceItem.y
            return sourceItem.mapToItem(root, 0, 0).y
        }

        Rectangle {
            anchors.fill: parent
            visible: dragOverlay.draggingTask
            color: Kirigami.Theme.alternateBackgroundColor
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            radius: Kirigami.Units.smallSpacing
            opacity: 0.9

            RowLayout {
                anchors.fill: parent
                visible: dragOverlay.draggingTask
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Kirigami.Units.smallSpacing
                    color: dragOverlay.draggingTask && root.draggedTaskData
                        ? root.draggedTaskData.categoryColor : (root.draggedCategoryData ? root.draggedCategoryData.color : Kirigami.Theme.highlightColor)
                    radius: width / 2
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: dragOverlay.draggingTask && root.draggedTaskData
                        ? root.draggedTaskData.title : (root.draggedCategoryData ? root.draggedCategoryData.name : "")
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

        }

        Item {
            id: categoryDragGhost
            objectName: "category-drag-preview-ghost"
            anchors.fill: parent
            visible: !dragOverlay.draggingTask
            opacity: 0.85

            Rectangle {
                objectName: "category-drag-preview-frame"
                anchors.fill: parent
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Kirigami.Theme.highlightColor
                border.width: 1
                radius: Kirigami.Units.smallSpacing
            }

            CategoryDragGroup {
                id: categoryDragPreview
                width: parent.width
                height: parent.height
                category: root.draggedCategoryData
                tasks: root.draggedCategoryTasks
                timeText: root.categoryTimeText(root.draggedCategoryId)
                showingTotalTime: root.totalTimeCategories[root.draggedCategoryId] === true
                isTaskActive: function(taskId) { return root.isTaskActive(taskId) }
                taskElapsedText: function(task) { return root.taskElapsedText(task) }
                objectNamePrefix: "category-drag-preview"
                onImplicitHeightChanged: {
                    if (!dragOverlay.draggingTask && root.draggedCategoryId.length > 0 && implicitHeight > 0) {
                        root.draggedCategoryGroupHeight = implicitHeight
                    }
                }
            }
        }
    }

    SettingsPage {
        id: settingsPage
        anchors.fill: parent
        visible: root.currentPage === "settings"
        board: root
        plasmoidConfiguration: root.plasmoidConfiguration
        onBackRequested: root.closeSettings()
    }

    ReportsView {
        id: reportsPage
        objectName: "reports-page"
        anchors.fill: parent
        visible: root.currentPage === "reports"
        board: root
        onBackRequested: root.closeReports()
    }

    Controls.Dialog {
        id: concurrentTimerResolutionDialog
        objectName: "concurrent-timer-resolution"
        parent: root
        modal: true
        closePolicy: Controls.Popup.NoAutoClose
        title: i18n("Keep one active timer")
        width: Math.min(root.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 28)
        anchors.centerIn: parent
        onRejected: root.cancelConcurrentTimerResolution()

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Turning off multiple timers stops every active timer except the one you choose.")
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.activeSessions

                delegate: Controls.RadioButton {
                    required property var modelData
                    Layout.fillWidth: true
                    checked: root.keepActiveTaskId === modelData.task_id
                    text: i18n("Keep tracking %1", modelData.taskTitle)
                    onClicked: root.keepActiveTaskId = modelData.task_id
                }
            }
        }

        footer: Controls.DialogButtonBox {
            PlasmaComponents.Button {
                text: i18n("Keep selected timer")
                enabled: root.isActiveTimerSelection(root.keepActiveTaskId)
                onClicked: root.resolveConcurrentTimerConflict()
            }

            PlasmaComponents.Button {
                text: i18n("Cancel")
                onClicked: root.cancelConcurrentTimerResolution()
            }
        }
    }

    Controls.Dialog {
        id: discardTaskChangesDialog
        parent: root
        modal: true
        title: i18n("Discard task changes?")
        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 24
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Your unsaved changes to this task will be lost.")
                wrapMode: Text.Wrap
            }
        }
        footer: Controls.DialogButtonBox {
            Controls.Button {
                text: i18n("Keep editing")
                onClicked: discardTaskChangesDialog.close()
            }
            Controls.Button {
                text: i18n("Discard changes")
                onClicked: {
                    discardTaskChangesDialog.close()
                    root.closeTaskDetails()
                }
            }
        }
    }

    Controls.Dialog {
        id: createWorkspaceDialog
        objectName: "create-workspace-dialog"
        parent: root
        modal: true
        title: i18n("Create workspace")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save

        onOpened: {
            workspaceName.text = ""
            workspaceName.forceActiveFocus()
        }
        onAccepted: {
            const workspace = Database.createWorkspace({ name: workspaceName.text })
            root.selectedWorkspaceId = workspace.id
            root.reload()
        }

        contentItem: PlasmaComponents.TextField {
            id: workspaceName
            objectName: "create-workspace-name"
            implicitWidth: Kirigami.Units.gridUnit * 20
            placeholderText: i18n("Workspace name")
            Accessible.name: i18n("Workspace name")
        }
    }

    Controls.Dialog {
        id: createTaskDialog
        objectName: "create-task-dialog"
        parent: root
        modal: true
        title: i18n("Create task")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save
        width: Math.min(root.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 24)

        onOpened: {
            const saveButton = standardButton(Controls.Dialog.Save)
            if (saveButton) saveButton.objectName = "create-task-save"
            taskTitle.text = ""
            taskDescription.text = ""
            taskStatus.currentIndex = 0
            taskCategory.currentIndex = 0
            taskTitle.forceActiveFocus()
        }
        onAccepted: {
            if (categoryModel.count === 0) {
                return
            }
            Database.createTask({
                title: taskTitle.text,
                details: taskDescription.text,
                status: taskStatus.currentValue,
                categoryId: categoryModel.get(taskCategory.currentIndex).id
            })
            root.reload()
        }

        contentItem: ColumnLayout {
            width: createTaskDialog.width - Kirigami.Units.largeSpacing * 2

            PlasmaComponents.TextField {
                id: taskTitle
                objectName: "create-task-title"
                Layout.fillWidth: true
                placeholderText: i18n("Task title")
                Accessible.name: i18n("Task title")
            }

            PlasmaComponents.ComboBox {
                id: taskCategory
                objectName: "create-task-category"
                Layout.fillWidth: true
                model: categoryModel
                textRole: "name"
                Accessible.name: i18n("Task category")
            }

            PlasmaComponents.ComboBox {
                id: taskStatus
                Layout.fillWidth: true
                model: ["backlog", "ready", "in_progress", "blocked", "completed"]
            }

            PlasmaComponents.TextArea {
                id: taskDescription
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                placeholderText: i18n("Description (Markdown supported)")
                wrapMode: TextEdit.Wrap
            }
        }
    }

    Controls.Dialog {
        id: createCategoryDialog
        objectName: "create-category-dialog"
        parent: root
        modal: true
        title: i18n("Create category")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save
        onOpened: {
            const saveButton = standardButton(Controls.Dialog.Save)
            if (saveButton) saveButton.objectName = "create-category-save"
            categoryName.text = ""
            categoryName.forceActiveFocus()
        }
        onAccepted: {
            Database.createCategory({
                name: categoryName.text,
                color: "#3daee9",
                workspaceId: root.selectedWorkspaceId
            })
            root.reload()
        }

        contentItem: PlasmaComponents.TextField {
            id: categoryName
            objectName: "create-category-name"
            implicitWidth: Kirigami.Units.gridUnit * 20
            placeholderText: i18n("Category name")
            Accessible.name: i18n("Category name")
        }
    }

    Controls.Dialog {
        id: categoryEditorDialog
        parent: root
        property string categoryId: ""
        property string errorText: ""
        modal: true
        title: i18n("Edit category")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save

        function openForCategory(category) {
            categoryId = category.id
            categoryEditorName.text = category.name
            categoryEditorColor.text = category.color
            categoryEditorWorkspace.currentIndex = Math.max(0, root.workspaceIndex(category.workspace_id))
            errorText = ""
            open()
            categoryEditorName.forceActiveFocus()
        }

        onAccepted: {
            try {
                Database.updateCategory({
                    id: categoryId,
                    name: categoryEditorName.text,
                    color: categoryEditorColor.text,
                    workspaceId: workspaceModel.get(categoryEditorWorkspace.currentIndex).id
                })
                root.reload()
            } catch (error) {
                errorText = error.message
            }
        }

        contentItem: ColumnLayout {
            implicitWidth: Kirigami.Units.gridUnit * 20

            PlasmaComponents.TextField {
                id: categoryEditorName
                Layout.fillWidth: true
                placeholderText: i18n("Category name")
                Accessible.name: i18n("Category name")
            }

            PlasmaComponents.ComboBox {
                id: categoryEditorWorkspace
                Layout.fillWidth: true
                model: workspaceModel
                textRole: "name"
                Accessible.name: i18n("Category workspace")
            }

            PlasmaComponents.TextField {
                id: categoryEditorColor
                Layout.fillWidth: true
                placeholderText: i18n("Color, for example #3daee9")
                Accessible.name: i18n("Category color")
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: categoryEditorDialog.errorText.length > 0
                text: categoryEditorDialog.errorText
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: categoryEditorDialog.errorText
            }
        }
    }

    Controls.Dialog {
        id: categoryDeleteDialog
        objectName: "category-delete-dialog"
        parent: root
        property string categoryId: ""
        property string targetCategoryName: ""
        property string errorText: ""
        modal: true
        title: i18n("Move category to trash")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Ok

        function openForCategory(category) {
            categoryId = category.id
            targetCategoryName = category.name
            errorText = ""
            open()
        }

        onAccepted: {
            try {
                Database.deleteCategory(categoryId)
                root.reload()
                close()
            } catch (error) {
                errorText = error.message
            }
        }

        contentItem: ColumnLayout {
            implicitWidth: Kirigami.Units.gridUnit * 24

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Move category \"%1\" and its tasks to the trash? You can restore it for 30 days before it is permanently deleted.", categoryDeleteDialog.targetCategoryName)
                wrapMode: Text.Wrap
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: categoryDeleteDialog.errorText.length > 0
                text: categoryDeleteDialog.errorText
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: categoryDeleteDialog.errorText
            }
        }
    }

    Controls.Dialog {
        id: moveTaskDialog
        parent: root
        property var task: null
        property var destinationCategories: []
        modal: true
        title: i18n("Move task to category")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Ok

        function openForTask(taskToMove) {
            task = taskToMove
            moveTaskWorkspace.currentIndex = Math.max(0, root.workspaceIndex(taskToMove.workspaceId))
            refreshCategories()
            moveTaskCategory.currentIndex = 0
            open()
            moveTaskCategory.forceActiveFocus()
        }

        function refreshCategories() {
            if (moveTaskWorkspace.currentIndex < 0 || moveTaskWorkspace.currentIndex >= workspaceModel.count) {
                destinationCategories = []
                return
            }
            destinationCategories = Database.listCategories(workspaceModel.get(moveTaskWorkspace.currentIndex).id)
            moveTaskCategory.currentIndex = destinationCategories.length > 0 ? 0 : -1
        }

        onAccepted: {
            if (!task || destinationCategories.length === 0 || moveTaskCategory.currentIndex < 0) {
                return
            }
            root.moveTaskById(task.taskId, null, destinationCategories[moveTaskCategory.currentIndex].id, "before")
        }

        contentItem: ColumnLayout {
            implicitWidth: Kirigami.Units.gridUnit * 20

            PlasmaComponents.ComboBox {
                id: moveTaskWorkspace
                Layout.fillWidth: true
                model: workspaceModel
                textRole: "name"
                Accessible.name: i18n("Destination workspace")
                onActivated: moveTaskDialog.refreshCategories()
            }

            PlasmaComponents.ComboBox {
                id: moveTaskCategory
                Layout.fillWidth: true
                model: moveTaskDialog.destinationCategories
                textRole: "name"
                Accessible.name: i18n("Destination category")
            }
        }
    }

    Controls.Dialog {
        id: categoryTrashDialog
        parent: root
        modal: true
        title: i18n("Category trash")
        standardButtons: Controls.Dialog.Close
        property var trashedCategories: []

        function openTrash() {
            trashedCategories = Database.listTrashedCategories(root.selectedWorkspaceId)
            open()
        }

        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Categories are permanently deleted 30 days after being moved here.")
                wrapMode: Text.Wrap
            }

            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true
                visible: categoryTrashDialog.trashedCategories.length === 0
                text: i18n("Trash is empty")
            }

            Repeater {
                model: categoryTrashDialog.trashedCategories

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.name + " (" + root.formatTimestamp(modelData.trashed_at_utc) + ")"
                        elide: Text.ElideRight
                    }

                    PlasmaComponents.Button {
                        text: i18n("Restore")
                        Accessible.name: i18n("Restore category %1", modelData.name)
                        onClicked: {
                            Database.restoreCategory(modelData.id)
                            categoryTrashDialog.trashedCategories = Database.listTrashedCategories(root.selectedWorkspaceId)
                            root.reload()
                        }
                    }
                }
            }
        }
    }

    Controls.Dialog {
        id: categoryManagementDialog
        parent: root
        modal: true
        title: i18n("Manage categories")
        standardButtons: Controls.Dialog.Close
        contentItem: Controls.ScrollView {
            implicitWidth: Kirigami.Units.gridUnit * 30
            implicitHeight: Kirigami.Units.gridUnit * 26
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    visible: categoryModel.count === 0
                    text: i18n("No active categories")
                }

                Repeater {
                    model: categoryModel

                    delegate: RowLayout {
                        required property var model
                        required property int index
                        Layout.fillWidth: true

                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.smallSpacing
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            color: model.color
                            radius: width / 2
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: model.name
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "go-up"
                            enabled: index > 0
                            Accessible.name: i18n("Move category %1 up", model.name)
                            onClicked: {
                                root.moveCategory(model.id, categoryModel.get(index - 1).id, "before")
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "go-down"
                            enabled: index + 1 < categoryModel.count
                            Accessible.name: i18n("Move category %1 down", model.name)
                            onClicked: {
                                root.moveCategory(model.id, categoryModel.get(index + 1).id, "after")
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "document-edit"
                            Accessible.name: i18n("Edit category %1", model.name)
                            onClicked: categoryEditorDialog.openForCategory(model)
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "user-trash"
                            Accessible.name: i18n("Move category %1 to trash", model.name)
                            onClicked: categoryDeleteDialog.openForCategory(model)
                        }
                    }
                }
            }
        }
    }

    TaskDetails {
        id: detailsDialog
        board: root
    }

}
