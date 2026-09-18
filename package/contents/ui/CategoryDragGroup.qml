import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    property var category: null
    property var tasks: []
    property string timeText: ""
    property bool showingTotalTime: false
    property var isTaskActive: function() { return false }
    property var taskElapsedText: function() { return "" }
    property string objectNamePrefix: ""
    property string accessibleName: ""

    objectName: root.objectNamePrefix
    Accessible.name: root.accessibleName
    Accessible.role: Accessible.Pane
    implicitHeight: content.childrenRect.height

    Column {
        id: content
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        CategoryHeader {
            width: parent.width
            visible: root.category !== null
            interactive: false
            objectNamePrefix: root.objectNamePrefix + "-category"
            categoryId: root.category ? root.category.id : ""
            categoryName: root.category ? root.category.name : ""
            categoryColor: root.category ? root.category.color : "transparent"
            collapsed: root.category && root.category.collapsed !== 0
            timeText: root.timeText
            showingTotalTime: root.showingTotalTime
        }

        Repeater {
            model: root.category ? root.tasks : []

            delegate: TaskCard {
                required property var modelData
                width: parent.width
                interactive: false
                objectNamePrefix: root.objectNamePrefix
                task: modelData
                active: root.isTaskActive(modelData.taskId)
                elapsedText: root.taskElapsedText(modelData)
            }
        }
    }
}
