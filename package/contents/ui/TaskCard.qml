import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Kirigami.AbstractCard {
    id: root

    required property var task
    required property bool active
    required property string elapsedText
    signal openRequested()
    signal timerRequested()
    signal statusRequested(string status)
    property bool canMoveUp: false
    property bool canMoveDown: false
    signal moveUpRequested()
    signal moveDownRequested()
    signal moveToCategoryRequested()
    signal dropRequested(string sourceTaskId)

    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: i18n("Open task %1", root.task.title)

    Keys.onReturnPressed: root.openRequested()
    Keys.onEnterPressed: root.openRequested()
    Keys.onSpacePressed: root.openRequested()

    contentItem: RowLayout {
        id: content
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.smallSpacing
            color: root.task.categoryColor
            radius: width / 2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.openRequested()
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.task.title
                font.bold: true
                elide: Text.ElideRight
                Accessible.name: i18n("Task: %1", root.task.title)
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: root.task.status.replace("_", " ")
                    color: Kirigami.Theme.disabledTextColor
                    Accessible.name: i18n("Status: %1", root.task.status.replace("_", " "))
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.active ? i18n("Tracking %1", root.elapsedText) : root.elapsedText
                    horizontalAlignment: Text.AlignRight
                    Accessible.name: root.active ? i18n("Timer active: %1", root.elapsedText) : i18n("Tracked time: %1", root.elapsedText)
                }
            }
        }

        PlasmaComponents.ToolButton {
            icon.name: root.active ? "media-playback-pause" : "media-playback-start"
            Accessible.name: root.active ? i18n("Pause timer for %1", root.task.title) : i18n("Start timer for %1", root.task.title)
            onClicked: root.timerRequested()
        }

        PlasmaComponents.ToolButton {
            id: dragHandle
            icon.name: "openhand-cursor"
            Accessible.name: i18n("Drag %1 to reorder or move it", root.task.title)
        }

        PlasmaComponents.ToolButton {
            id: taskActionsButton
            icon.name: "overflow-menu"
            Accessible.name: i18n("Task actions for %1", root.task.title)
            onClicked: taskActionsMenu.popup(taskActionsButton, 0, taskActionsButton.height)
        }
    }

    Drag.active: dragHandler.active
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.keys: ["application/x-worktodo-task"]
    Drag.mimeData: ({ "application/x-worktodo-task": root.task.taskId })

    DragHandler {
        id: dragHandler
        parent: dragHandle
        target: root
        onActiveChanged: {
            root.opacity = active ? 0.55 : 1.0
            if (!active) {
                root.Drag.drop()
            }
        }
    }

    DropArea {
        anchors.fill: parent
        keys: ["application/x-worktodo-task"]
        onDropped: function(drop) {
            if (drop.source && drop.source.task && drop.source.task.taskId !== root.task.taskId) {
                root.dropRequested(drop.source.task.taskId)
                drop.acceptProposedAction()
            }
        }
    }

    Controls.Menu {
        id: taskActionsMenu

        Controls.MenuItem {
            text: i18n("Move up")
            enabled: root.canMoveUp
            Accessible.name: i18n("Move %1 up", root.task.title)
            onTriggered: root.moveUpRequested()
        }

        Controls.MenuItem {
            text: i18n("Move down")
            enabled: root.canMoveDown
            Accessible.name: i18n("Move %1 down", root.task.title)
            onTriggered: root.moveDownRequested()
        }

        Controls.MenuSeparator {}

        Controls.MenuItem {
            text: i18n("Move to category...")
            Accessible.name: i18n("Move %1 to another category", root.task.title)
            onTriggered: root.moveToCategoryRequested()
        }
    }

}
