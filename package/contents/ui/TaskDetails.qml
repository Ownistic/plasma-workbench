import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../code/Database.js" as Database
import "../code/Markdown.js" as Markdown

Controls.Dialog {
    id: root

    required property var board
    property string taskId: ""
    property var task: null
    modal: true
    title: root.task ? root.task.title : i18n("Task details")
    standardButtons: Controls.Dialog.Close
    width: Math.min(root.board.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 32)
    height: Math.min(root.board.height - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 42)

    function openForTask(id) {
        root.taskId = id
        root.task = Database.getTask(id)
        if (!root.task) {
            return
        }
        titleField.text = root.task.title
        descriptionField.text = root.task.details
        statusField.currentIndex = statusField.indexOfValue(root.task.status)
        for (let index = 0; index < root.board.categoryModel.count; index += 1) {
            if (root.board.categoryModel.get(index).id === root.task.category_id) {
                categoryField.currentIndex = index
                break
            }
        }
        root.open()
    }

    function saveTask() {
        if (!root.task) {
            return
        }
        Database.updateTask({ id: root.taskId, title: titleField.text, details: descriptionField.text })
        const categoryId = root.board.categoryModel.get(categoryField.currentIndex).id
        if (categoryId !== root.task.category_id) {
            Database.moveTask({ taskId: root.taskId, targetCategoryId: categoryId, placement: "before" })
        }
        if (statusField.currentValue !== root.task.status) {
            Database.changeStatus(root.taskId, statusField.currentValue)
        }
        root.task = Database.getTask(root.taskId)
        root.board.reload()
    }

    contentItem: Controls.ScrollView {
        implicitWidth: Kirigami.Units.gridUnit * 30
        implicitHeight: Kirigami.Units.gridUnit * 36
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: i18n("Task title")
                onEditingFinished: root.saveTask()
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.ComboBox {
                    id: categoryField
                    Layout.fillWidth: true
                    model: root.board.categoryModel
                    textRole: "name"
                }

                PlasmaComponents.ComboBox {
                    id: statusField
                    Layout.fillWidth: true
                    model: ["backlog", "ready", "in_progress", "blocked", "completed"]
                }
            }

            PlasmaComponents.TextArea {
                id: descriptionField
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                placeholderText: i18n("Description (Markdown supported)")
                wrapMode: TextEdit.Wrap
            }

            PlasmaComponents.Button {
                Layout.alignment: Qt.AlignRight
                text: i18n("Save changes")
                onClicked: root.saveTask()
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Preview")
            }

            Text {
                Layout.fillWidth: true
                text: Markdown.localOnly(descriptionField.text)
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                color: Kirigami.Theme.textColor
                onLinkActivated: function(link) {}
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.task ? i18n("Tracked time: %1", root.board.taskElapsedText(root.task)) : ""
                }

                PlasmaComponents.Button {
                    text: root.task && root.board.activeSession && root.board.activeSession.task_id === root.taskId
                        ? i18n("Pause") : i18n("Start")
                    onClicked: {
                        root.board.toggleTimer({ taskId: root.taskId })
                        root.task = Database.getTask(root.taskId)
                    }
                }
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Work sessions")
            }

            Repeater {
                model: root.task ? root.task.workSessions : []

                delegate: PlasmaComponents.Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.started_at_utc + (modelData.ended_at_utc ? " - " + modelData.ended_at_utc : i18n(" (active)"))
                    wrapMode: Text.Wrap
                }
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Status history")
            }

            Repeater {
                model: root.task ? root.task.statusEvents : []

                delegate: PlasmaComponents.Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.occurred_at_utc + ": " + modelData.status.replace("_", " ")
                        + (modelData.manually_edited ? i18n(" (corrected)") : "")
                    wrapMode: Text.Wrap
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    text: i18n("Archive task")
                    onClicked: {
                        Database.archiveTask(root.taskId)
                        root.board.reload()
                        root.close()
                    }
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: i18n("Delete task")
                    onClicked: deleteConfirmation.open()
                }
            }
        }
    }

    Controls.Dialog {
        id: deleteConfirmation
        parent: root.parent
        modal: true
        title: i18n("Delete task?")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Yes
        contentItem: PlasmaComponents.Label {
            implicitWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18n("Deleting this task also permanently deletes its work-session and status history.")
        }
        onAccepted: {
            Database.deleteTask(root.taskId)
            root.board.reload()
            root.close()
        }
    }
}
