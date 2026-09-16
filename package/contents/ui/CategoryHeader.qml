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
    required property string timeText
    required property bool showingTotalTime
    signal editRequested()
    signal deleteRequested()
    signal collapseRequested()
    signal timeDisplayToggleRequested()
    signal dragStarted(var dragItem, var dragGroup)
    signal dragPositionChanged(var dragItem)
    signal dragPreviewRequested(string sourceCategoryId, string placement, var targetItem)
    signal dragFinished()
    signal taskPreviewRequested(string taskId, var targetItem)
    signal taskDropped(string taskId)
    signal categoryDropped(string categoryId, string placement)
    readonly property bool dragging: categoryDragHandler.active
    property var dragGroup: null
    property real dragOriginX: 0
    property real dragOriginY: 0

    text: root.categoryName
    objectName: "category-header-" + root.categoryId

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

        Controls.ToolButton {
            id: categoryTimeButton
            objectName: "category-time-" + root.categoryId
            text: root.timeText
            Accessible.name: root.showingTotalTime
                ? i18n("Total tracked time for %1: %2. Click to show today's time.", root.categoryName, root.timeText)
                : i18n("Today's tracked time for %1: %2. Click to show total time.", root.categoryName, root.timeText)
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: root.showingTotalTime
                ? i18n("Show today's tracked time") : i18n("Show total tracked time")
            onClicked: root.timeDisplayToggleRequested()
        }

        PlasmaComponents.ToolButton {
            icon.name: root.collapsed ? "go-down" : "go-up"
            Accessible.name: root.collapsed ? i18n("Expand category %1", root.categoryName)
                : i18n("Collapse category %1", root.categoryName)
            onClicked: root.collapseRequested()
        }

        PlasmaComponents.ToolButton {
            id: categoryDragHandle
            objectName: "category-drag-handle-" + root.categoryId
            icon.name: "drag-handle-symbolic"
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
    Drag.keys: ["application/x-workbench-category"]
    Drag.mimeData: ({ "application/x-workbench-category": root.categoryId })

    DragHandler {
        id: categoryDragHandler
        parent: categoryDragHandle
        target: root
        onActiveChanged: {
            if (active) {
                root.dragOriginX = root.x
                root.dragOriginY = root.y
                root.dragStarted(root, root.dragGroup)
            }
            root.opacity = active ? 0 : 1.0
            if (!active) {
                root.Drag.drop()
                root.x = root.dragOriginX
                root.y = root.dragOriginY
                root.dragFinished()
            }
        }
        onTranslationChanged: root.dragPositionChanged(root)
    }

    DropArea {
        anchors.fill: parent
        keys: ["application/x-workbench-task", "application/x-workbench-category"]
        function placementFor(drag) {
            return drag.y >= height / 2 ? "after" : "before"
        }
        onEntered: function(drag) {
            if (drag.source && drag.source.task) {
                root.taskPreviewRequested(drag.source.task.taskId, root.parent)
            } else if (drag.source && drag.source.categoryId && drag.source.categoryId !== root.categoryId) {
                root.dragPreviewRequested(drag.source.categoryId, placementFor(drag), root.dragGroup || root.parent)
            }
        }
        onPositionChanged: function(drag) {
            if (drag.source && drag.source.task) {
                root.taskPreviewRequested(drag.source.task.taskId, root.parent)
            } else if (drag.source && drag.source.categoryId && drag.source.categoryId !== root.categoryId) {
                root.dragPreviewRequested(drag.source.categoryId, placementFor(drag), root.dragGroup || root.parent)
            }
        }
        onDropped: function(drop) {
            if (drop.source && drop.source.task && drop.source.task.taskId) {
                root.taskDropped(drop.source.task.taskId)
                drop.acceptProposedAction()
            } else if (drop.source && drop.source.categoryId && drop.source.categoryId !== root.categoryId) {
                root.categoryDropped(drop.source.categoryId, placementFor(drop))
                drop.acceptProposedAction()
            }
        }
    }
}
