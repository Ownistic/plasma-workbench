import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../code/Database.js" as Database

ColumnLayout {
    id: root

    required property var board
    property string message: ""
    property bool failure: false

    function addStatus() {
        try {
            Database.createWorkflowStatus({
                workspaceId: root.board.selectedWorkspaceId,
                name: newStatusName.text,
                isCompleted: terminalStatus.checked
            })
            root.board.refreshWorkflowStatuses()
            root.failure = false
            root.message = i18n("Added %1 to this workbench’s workflow.", newStatusName.text.trim())
            newStatusName.text = ""
            terminalStatus.checked = false
            newStatusName.forceActiveFocus()
        } catch (error) {
            root.failure = true
            root.message = error.message || i18n("Could not add the status.")
        }
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        Layout.fillWidth: true
        level: 3
        text: i18n("Local workflow")
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        text: i18n("Statuses belong to this workbench. Add the states your team uses, then map Plane states to them below.")
    }

    Repeater {
        model: root.board.workflowStatuses

        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: modelData.name
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                visible: modelData.isCompleted
                text: i18n("Completes tasks")
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.TextField {
            id: newStatusName
            Layout.fillWidth: true
            placeholderText: i18n("New status name")
            Accessible.name: i18n("New workflow status name")
            onAccepted: root.addStatus()
        }

        PlasmaComponents.CheckBox {
            id: terminalStatus
            text: i18n("Completes tasks")
            Accessible.description: i18n("Stops active timers and marks tasks completed when selected.")
        }

        PlasmaComponents.Button {
            text: i18n("Add status")
            enabled: newStatusName.text.trim().length > 0
            onClicked: root.addStatus()
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: root.message.length > 0
        wrapMode: Text.Wrap
        color: root.failure ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
        text: root.message
    }
}
