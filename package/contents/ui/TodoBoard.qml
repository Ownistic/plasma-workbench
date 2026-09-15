import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import io.github.ownisticapps.worktodo.time as WorkTodoTime

import "../code/Database.js" as Database

Item {
    id: root

    required property var plasmoidConfiguration
    property var selectedStatuses: []
    property var activeSession: null
    property int elapsedRefresh: 0
    readonly property bool hasActiveSession: root.activeSession !== null
    readonly property string activeElapsedText: root.hasActiveSession
        ? root.formatSeconds(root.elapsedSeconds(root.activeSession.started_at_utc)) : ""
    readonly property string activeTaskSummary: root.hasActiveSession
        ? i18n("Tracking %1", root.activeElapsedText) : i18n("No active timer")
    readonly property string reportTimezone: WorkTodoTime.TimeMath.isValidTimeZone(root.plasmoidConfiguration.reportTimezone)
        ? root.plasmoidConfiguration.reportTimezone : WorkTodoTime.TimeMath.systemTimeZoneId()
    readonly property int firstDayOfWeek: root.plasmoidConfiguration.firstDayOfWeek >= 1
        && root.plasmoidConfiguration.firstDayOfWeek <= 7 ? root.plasmoidConfiguration.firstDayOfWeek : 1

    ListModel { id: taskModel }
    ListModel { id: categoryModel }

    function formatSeconds(seconds) {
        const safeSeconds = Math.max(0, Math.floor(seconds))
        const hours = Math.floor(safeSeconds / 3600)
        const minutes = Math.floor((safeSeconds % 3600) / 60)
        const remainingSeconds = safeSeconds % 60
        return (hours < 10 ? "0" : "") + hours + ":"
            + (minutes < 10 ? "0" : "") + minutes + ":"
            + (remainingSeconds < 10 ? "0" : "") + remainingSeconds
    }

    function elapsedSeconds(startedAtUtc) {
        if (!startedAtUtc) {
            return 0
        }
        return (Date.now() - Date.parse(startedAtUtc)) / 1000
    }

    function taskElapsedText(task) {
        const total = Number(task.trackedSeconds || 0)
        return root.formatSeconds(total + (task.activeStartedAt ? root.elapsedSeconds(task.activeStartedAt) : 0))
    }

    function categoryForId(categoryId) {
        for (let index = 0; index < taskModel.count; index += 1) {
            const task = taskModel.get(index)
            if (task.categoryId === categoryId) {
                return task
            }
        }
        return { categoryName: "", categoryColor: Kirigami.Theme.disabledTextColor }
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
        root.activeSession = Database.getActiveSession()
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
        if (root.activeSession && root.activeSession.task_id === task.taskId) {
            Database.stopTimer(task.taskId)
        } else {
            Database.startTimer(task.taskId, root.reportTimezone)
        }
        root.reload()
    }

    Component.onCompleted: {
        Database.initialize()
        const configuredStatuses = root.plasmoidConfiguration.defaultStatusFilter.split(",")
        root.selectedStatuses = configuredStatuses.filter(function(status) {
            return ["backlog", "ready", "in_progress", "blocked", "completed"].indexOf(status) !== -1
        })
        root.reload()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.hasActiveSession
        onTriggered: root.elapsedRefresh += 1
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
            visible: taskModel.count === 0
            text: i18n("No tasks match these filters")
            helpfulAction: Controls.Action {
                text: i18n("Create task")
                onTriggered: createTaskDialog.open()
            }
        }

        ListView {
            id: taskList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: taskModel.count > 0
            clip: true
            spacing: Kirigami.Units.smallSpacing
            model: taskModel
            section.property: "categoryId"
            section.delegate: CategoryHeader {
                readonly property var category: root.categoryForId(section)
                categoryName: category.categoryName
                categoryColor: category.categoryColor
                width: taskList.width
            }
            delegate: TaskCard {
                required property var model
                width: taskList.width
                task: model
                active: root.activeSession && root.activeSession.task_id === model.taskId
                elapsedText: root.taskElapsedText(model)
                onTimerRequested: root.toggleTimer(model)
                onOpenRequested: detailsDialog.openForTask(model.taskId)
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

    TaskDetails {
        id: detailsDialog
        board: root
    }

    ReportsView {
        id: reportsDialog
        board: root
    }
}
