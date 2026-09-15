import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "time" as WorkTodoTime

import "../code/Database.js" as Database

Item {
    id: root

    required property var plasmoidConfiguration
    required property var plasmoidRoot
    property var selectedStatuses: []
    readonly property var activeSession: root.plasmoidRoot.activeSession
    readonly property bool hasActiveSession: root.plasmoidRoot.hasActiveSession
    readonly property string activeElapsedText: root.plasmoidRoot.activeElapsedText
    readonly property string activeTaskSummary: root.plasmoidRoot.activeTaskSummary
    readonly property string reportTimezone: WorkTodoTime.TimeMath.isValidTimeZone(root.plasmoidConfiguration.reportTimezone)
        ? root.plasmoidConfiguration.reportTimezone : WorkTodoTime.TimeMath.systemTimeZoneId()
    readonly property int firstDayOfWeek: root.plasmoidConfiguration.firstDayOfWeek >= 1
        && root.plasmoidConfiguration.firstDayOfWeek <= 7 ? root.plasmoidConfiguration.firstDayOfWeek : 1

    ListModel { id: taskModel }
    ListModel { id: categoryModel }

    function formatSeconds(seconds) {
        return root.plasmoidRoot.formatSeconds(seconds)
    }

    function taskElapsedText(task) {
        const total = Number(task.trackedSeconds || 0)
        root.plasmoidRoot.elapsedRefresh
        return root.plasmoidRoot.formatSeconds(total + (task.activeStartedAt
            ? root.plasmoidRoot.elapsedSeconds(task.activeStartedAt) : 0))
    }

    function reload() {
        const tasks = Database.listTasks({
            statuses: root.selectedStatuses,
            showArchived: root.plasmoidConfiguration.showArchivedTasks
        })
        const categories = Database.listCategories()
        taskModel.clear()
        categoryModel.clear()
        for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex += 1) {
            categoryModel.append(categories[categoryIndex])
        }
        for (let taskIndex = 0; taskIndex < tasks.length; taskIndex += 1) {
            taskModel.append(tasks[taskIndex])
        }
        root.plasmoidRoot.activeSession = Database.getActiveSession()
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
        if (root.plasmoidRoot.activeSession && root.plasmoidRoot.activeSession.task_id === task.taskId) {
            Database.stopTimer(task.taskId)
        } else {
            Database.startTimer(task.taskId, root.reportTimezone)
        }
        root.reload()
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

    function moveTask(task, targetTask, placement) {
        if (!targetTask) {
            return
        }
        Database.moveTask({
            taskId: task.taskId,
            targetCategoryId: targetTask.categoryId,
            targetTaskId: targetTask.taskId,
            placement: placement
        })
        root.reload()
    }

    function moveTaskById(taskId, targetTaskId, targetCategoryId, placement) {
        Database.moveTask({
            taskId: taskId,
            targetCategoryId: targetCategoryId,
            targetTaskId: targetTaskId || null,
            placement: placement || "before"
        })
        root.reload()
    }

    Component.onCompleted: {
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkTodoTime.TimeMath.isValidTimeZone(timezoneId)
        })
        Database.initialize()
        const configuredStatuses = root.plasmoidConfiguration.defaultStatusFilter.split(",")
        root.selectedStatuses = configuredStatuses.filter(function(status) {
            return ["backlog", "ready", "in_progress", "blocked", "completed"].indexOf(status) !== -1
        })
        root.reload()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 2
                text: i18n("Work Todo")
            }

            PlasmaComponents.Label {
                text: root.hasActiveSession ? root.activeElapsedText : i18n("No timer")
                Accessible.name: root.activeTaskSummary
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
                icon.name: "office-chart-bar"
                Accessible.name: i18n("Open reports")
                onClicked: reportsDialog.openReport(false)
            }
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
                    model: categoryModel

                    delegate: Column {
                        required property var model
                        readonly property string currentCategoryId: model.id
                        width: categoryColumn.width
                        spacing: Kirigami.Units.smallSpacing

                        CategoryHeader {
                            width: parent.width
                            categoryId: model.id
                            categoryName: model.name
                            categoryColor: model.color
                            collapsed: model.collapsed !== 0
                            onCollapseRequested: {
                                Database.updateCategory({ id: model.id, collapsed: model.collapsed === 0 })
                                root.reload()
                            }
                            onEditRequested: categoryEditorDialog.openForCategory(model)
                            onDeleteRequested: categoryDeleteDialog.openForCategory(model)
                            onTaskDropped: function(taskId) {
                                root.moveTaskById(taskId, null, model.id, "before")
                            }
                            onCategoryDropped: function(categoryId) {
                                Database.moveCategory({
                                    categoryId: categoryId,
                                    targetCategoryId: model.id,
                                    placement: "before"
                                })
                                root.reload()
                            }
                        }

                        Repeater {
                            model: taskModel

                            delegate: TaskCard {
                                required property var model
                                width: parent.width
                                visible: model.categoryId === currentCategoryId && model.categoryCollapsed === 0
                                height: visible ? implicitHeight : 0
                                task: model
                                active: root.activeSession && root.activeSession.task_id === model.taskId
                                elapsedText: root.taskElapsedText(model)
                                canMoveUp: root.adjacentTask(model, -1) !== null
                                canMoveDown: root.adjacentTask(model, 1) !== null
                                onTimerRequested: root.toggleTimer(model)
                                onOpenRequested: detailsDialog.openForTask(model.taskId)
                                onMoveUpRequested: root.moveTask(model, root.adjacentTask(model, -1), "before")
                                onMoveDownRequested: root.moveTask(model, root.adjacentTask(model, 1), "after")
                                onMoveToCategoryRequested: moveTaskDialog.openForTask(model)
                                onDropRequested: function(sourceTaskId) {
                                    root.moveTaskById(sourceTaskId, model.taskId, model.categoryId, "before")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Controls.Dialog {
        id: createTaskDialog
        modal: true
        title: i18n("Create task")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save
        width: Math.min(root.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 24)

        onOpened: {
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
                Layout.fillWidth: true
                placeholderText: i18n("Task title")
            }

            PlasmaComponents.ComboBox {
                id: taskCategory
                Layout.fillWidth: true
                model: categoryModel
                textRole: "name"
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
        modal: true
        title: i18n("Create category")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save
        onOpened: {
            categoryName.text = ""
            categoryName.forceActiveFocus()
        }
        onAccepted: {
            Database.createCategory({ name: categoryName.text, color: "#3daee9" })
            root.reload()
        }

        contentItem: PlasmaComponents.TextField {
            id: categoryName
            implicitWidth: Kirigami.Units.gridUnit * 20
            placeholderText: i18n("Category name")
        }
    }

    Controls.Dialog {
        id: categoryEditorDialog
        property string categoryId: ""
        property string errorText: ""
        modal: true
        title: i18n("Edit category")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save

        function openForCategory(category) {
            categoryId = category.id
            categoryEditorName.text = category.name
            categoryEditorColor.text = category.color
            errorText = ""
            open()
            categoryEditorName.forceActiveFocus()
        }

        onAccepted: {
            try {
                Database.updateCategory({ id: categoryId, name: categoryEditorName.text, color: categoryEditorColor.text })
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
        property string categoryId: ""
        property string targetCategoryName: ""
        property string errorText: ""
        modal: true
        title: i18n("Delete category")
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
                text: i18n("Delete category \"%1\"? This is only possible after all of its tasks have been moved, archived, or deleted.", categoryDeleteDialog.targetCategoryName)
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
        property var task: null
        modal: true
        title: i18n("Move task to category")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Ok

        function openForTask(taskToMove) {
            task = taskToMove
            moveTaskCategory.currentIndex = 0
            open()
            moveTaskCategory.forceActiveFocus()
        }

        onAccepted: {
            if (!task || categoryModel.count === 0) {
                return
            }
            Database.moveTask({
                taskId: task.taskId,
                targetCategoryId: categoryModel.get(moveTaskCategory.currentIndex).id
            })
            root.reload()
        }

        contentItem: PlasmaComponents.ComboBox {
            id: moveTaskCategory
            implicitWidth: Kirigami.Units.gridUnit * 20
            model: categoryModel
            textRole: "name"
            Accessible.name: i18n("Destination category")
        }
    }

    TaskDetails {
        id: detailsDialog
        board: root
    }

    ReportsView {
        id: reportsDialog
        board: root
    }
}
