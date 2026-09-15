import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.ListSectionHeader {
    id: root

    required property string categoryName
    required property string categoryColor
    required property string categoryId
    required property bool collapsed
    signal editRequested()
    signal deleteRequested()
    signal collapseRequested()
    signal taskDropped(string taskId)
    signal categoryDropped(string categoryId)

    text: root.categoryName

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.smallSpacing
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            color: root.categoryColor
            radius: width / 2
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.categoryName
            font.bold: true
            elide: Text.ElideRight
            Accessible.name: i18n("Category: %1", root.categoryName)
        }

        PlasmaComponents.ToolButton {
            icon.name: root.collapsed ? "go-down" : "go-up"
            Accessible.name: root.collapsed ? i18n("Expand category %1", root.categoryName)
                : i18n("Collapse category %1", root.categoryName)
            onClicked: root.collapseRequested()
        }

        PlasmaComponents.ToolButton {
            id: categoryDragHandle
            icon.name: "openhand-cursor"
            Accessible.name: i18n("Drag category %1 to reorder it", root.categoryName)
        }

        PlasmaComponents.ToolButton {
            id: categoryActionsButton
            icon.name: "overflow-menu"
            Accessible.name: i18n("Category actions for %1", root.categoryName)
            onClicked: categoryActionsMenu.popup()
        }
    }

    Controls.Menu {
        id: categoryActionsMenu

        Controls.MenuItem {
            text: i18n("Edit category...")
            Accessible.name: i18n("Rename or recolor category %1", root.categoryName)
            onTriggered: root.editRequested()
        }

        Controls.MenuSeparator {}

        Controls.MenuItem {
            text: i18n("Delete category...")
            Accessible.name: i18n("Delete category %1", root.categoryName)
            onTriggered: root.deleteRequested()
        }
    }

    Drag.active: categoryDragHandler.active
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.keys: ["application/x-worktodo-category"]
    Drag.mimeData: ({ "application/x-worktodo-category": root.categoryId })

    DragHandler {
        id: categoryDragHandler
        parent: categoryDragHandle
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
        keys: ["application/x-worktodo-task", "application/x-worktodo-category"]
        onDropped: function(drop) {
            if (drop.source && drop.source.task && drop.source.task.taskId) {
                root.taskDropped(drop.source.task.taskId)
                drop.acceptProposedAction()
            } else if (drop.source && drop.source.categoryId && drop.source.categoryId !== root.categoryId) {
                root.categoryDropped(drop.source.categoryId)
                drop.acceptProposedAction()
            }
        }
    }
}
