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
    readonly property bool hasManualCorrections: root.task && (
        root.task.workSessions.some(function(session) { return session.manually_edited })
        || root.task.statusEvents.some(function(event) { return event.manually_edited })
    )
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
        const categoryId = root.board.categoryModel.get(categoryField.currentIndex).id
        Database.saveTask({
            id: root.taskId,
            title: titleField.text,
            details: descriptionField.text,
            categoryId: categoryId,
            status: statusField.currentValue
        })
        root.task = Database.getTask(root.taskId)
        root.board.reload()
    }

    function refreshTask() {
        root.task = Database.getTask(root.taskId)
        root.board.reload()
    }

    function validUtcInstant(value) {
        if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) {
            return false
        }
        const date = new Date(value)
        return !isNaN(date.getTime()) && date.toISOString() === value
    }

    function openWorkSessionEditor(session) {
        workSessionEditor.session = session
        workSessionEditor.title = session ? i18n("Edit work session") : i18n("Add work session")
        workSessionStartField.text = session ? session.started_at_utc : ""
        workSessionEndField.text = session ? session.ended_at_utc : ""
        workSessionError.text = ""
        workSessionEditor.open()
    }

    function openStatusEventEditor(event) {
        statusEventEditor.event = event
        statusEventField.currentIndex = statusEventField.indexOfValue(event.status)
        statusEventTimeField.text = event.occurred_at_utc
        statusEventError.text = ""
        statusEventEditor.open()
    }

    function confirmCorrectionDeletion(kind, id, label) {
        correctionDeletion.kind = kind
        correctionDeletion.itemId = id
        correctionDeletion.itemLabel = label
        correctionDeletion.open()
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
                Accessible.name: i18n("Save task changes")
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

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Report timezone: %1", root.board.reportTimezone)
                wrapMode: Text.Wrap
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.hasManualCorrections
                text: i18n("Manual corrections are present for this task.")
                color: Kirigami.Theme.positiveTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }

            PlasmaComponents.Button {
                Layout.alignment: Qt.AlignLeft
                text: i18n("Add manual work session")
                Accessible.name: text
                onClicked: root.openWorkSessionEditor(null)
            }

            Repeater {
                model: root.task ? root.task.workSessions : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.started_at_utc + (modelData.ended_at_utc
                            ? " - " + modelData.ended_at_utc : i18n(" (active)"))
                            + (modelData.manually_edited ? i18n(" (corrected)") : "")
                        wrapMode: Text.Wrap
                    }

                    PlasmaComponents.Button {
                        text: i18n("Edit")
                        Accessible.name: i18n("Edit work session starting %1", modelData.started_at_utc)
                        onClicked: root.openWorkSessionEditor(modelData)
                    }

                    PlasmaComponents.Button {
                        text: i18n("Delete")
                        Accessible.name: i18n("Delete work session starting %1", modelData.started_at_utc)
                        onClicked: root.confirmCorrectionDeletion("workSession", modelData.id,
                            i18n("work session starting %1", modelData.started_at_utc))
                    }
                }
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Status history")
            }

            Repeater {
                model: root.task ? root.task.statusEvents : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: modelData.occurred_at_utc + ": " + modelData.status.replace("_", " ")
                            + (modelData.manually_edited ? i18n(" (corrected)") : "")
                        wrapMode: Text.Wrap
                    }

                    PlasmaComponents.Button {
                        text: i18n("Edit")
                        Accessible.name: i18n("Edit status event at %1", modelData.occurred_at_utc)
                        onClicked: root.openStatusEventEditor(modelData)
                    }

                    PlasmaComponents.Button {
                        text: i18n("Delete")
                        Accessible.name: i18n("Delete status event at %1", modelData.occurred_at_utc)
                        onClicked: root.confirmCorrectionDeletion("statusEvent", modelData.id,
                            i18n("status event at %1", modelData.occurred_at_utc))
                    }
                }
            }

            PlasmaComponents.Label {
                id: correctionError
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
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
        id: correctionDeletion
        parent: root.parent
        modal: true
        property string kind: ""
        property string itemId: ""
        property string itemLabel: ""
        title: i18n("Delete correction?")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Yes
        contentItem: PlasmaComponents.Label {
            width: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: i18n("Delete %1 permanently?", correctionDeletion.itemLabel)
            Accessible.name: text
        }
        onAccepted: {
            try {
                if (kind === "workSession") {
                    Database.deleteWorkSession(itemId)
                } else {
                    Database.deleteStatusEvent(itemId)
                }
                root.refreshTask()
            } catch (error) {
                correctionError.text = error.message
            }
        }
    }

    Controls.Dialog {
        id: workSessionEditor
        parent: root.parent
        modal: true
        property var session: null
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save
        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: i18n("Enter UTC ISO timestamps, for example 2026-01-31T09:30:00.000Z.")
                wrapMode: Text.Wrap
            }

            PlasmaComponents.TextField {
                id: workSessionStartField
                Layout.fillWidth: true
                placeholderText: i18n("Start time (UTC ISO)")
                Accessible.name: i18n("Work session start time in UTC ISO format")
            }

            PlasmaComponents.TextField {
                id: workSessionEndField
                Layout.fillWidth: true
                placeholderText: i18n("End time (UTC ISO)")
                Accessible.name: i18n("Work session end time in UTC ISO format")
            }

            PlasmaComponents.Label {
                id: workSessionError
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }
        }
        onAccepted: {
            if (!root.validUtcInstant(workSessionStartField.text)
                || !root.validUtcInstant(workSessionEndField.text)) {
                workSessionError.text = i18n("Start and end times must be valid UTC ISO timestamps.")
                return
            }
            try {
                if (session) {
                    Database.updateWorkSession({
                        id: session.id,
                        startedAtUtc: workSessionStartField.text,
                        endedAtUtc: workSessionEndField.text
                    })
                } else {
                    Database.createWorkSession({
                        taskId: root.taskId,
                        startedAtUtc: workSessionStartField.text,
                        endedAtUtc: workSessionEndField.text,
                        timezoneId: root.board.reportTimezone
                    })
                }
                root.refreshTask()
                close()
            } catch (error) {
                workSessionError.text = error.message
            }
        }
    }

    Controls.Dialog {
        id: statusEventEditor
        parent: root.parent
        modal: true
        property var event: null
        title: i18n("Edit status event")
        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Save
        contentItem: ColumnLayout {
            width: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.ComboBox {
                id: statusEventField
                Layout.fillWidth: true
                model: ["backlog", "ready", "in_progress", "blocked", "completed"]
                Accessible.name: i18n("Status event status")
            }

            PlasmaComponents.TextField {
                id: statusEventTimeField
                Layout.fillWidth: true
                placeholderText: i18n("Event time (UTC ISO)")
                Accessible.name: i18n("Status event time in UTC ISO format")
            }

            PlasmaComponents.Label {
                id: statusEventError
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Accessible.name: text
            }
        }
        onAccepted: {
            if (!root.validUtcInstant(statusEventTimeField.text)) {
                statusEventError.text = i18n("The event time must be a valid UTC ISO timestamp.")
                return
            }
            try {
                Database.updateStatusEvent({
                    id: event.id,
                    status: statusEventField.currentValue,
                    occurredAtUtc: statusEventTimeField.text
                })
                root.refreshTask()
                close()
            } catch (error) {
                statusEventError.text = error.message
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
            width: Kirigami.Units.gridUnit * 24
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
