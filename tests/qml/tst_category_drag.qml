import QtQuick
import QtTest

import "../../package/contents/ui" as WorkTodoUi
import "../../package/contents/ui/time" as WorkTodoTime
import "../../package/contents/code/Database.js" as Database

TestCase {
    id: testCase
    name: "CategoryDragE2E"
    when: windowShown

    property int databaseNumber: 0
    property var board: null

    QtObject {
        id: testConfiguration
        property string reportTimezone: "Etc/UTC"
        property int firstDayOfWeek: 1
        property bool use24HourTime: true
        property int unusualSessionHours: 16
        property bool showArchivedTasks: false
        property string defaultStatusFilter: "backlog,ready,in_progress,blocked,completed"
    }

    QtObject {
        id: testPlasmoidRoot
        property var activeSession: null
        property bool hasActiveSession: false
        property string activeElapsedText: ""
        property int elapsedRefresh: 0
        function formatSeconds(seconds) {
            return "00:00:00"
        }
        function elapsedSeconds(utc) {
            return 0
        }
    }

    Item {
        id: stage
        parent: testCase.window ? testCase.window.contentItem : null
        width: 600
        height: 1000
    }

    Component {
        id: boardComponent

        WorkTodoUi.TodoBoard {
            width: 560
            height: 900
            plasmoidConfiguration: testConfiguration
            plasmoidRoot: testPlasmoidRoot
        }
    }

    function init() {
        databaseNumber += 1
        Database.configureDatabaseForTests("worktodo-category-drag-" + Date.now() + "-" + databaseNumber)
        Database.setTimeZoneValidator(function(timezoneId) {
            return WorkTodoTime.TimeMath.isValidTimeZone(timezoneId)
        })
        Database.initialize()

        const first = Database.createCategory({ name: "First", color: "#3daee9" })
        const second = Database.createCategory({ name: "Second", color: "#8ae234" })
        Database.createTask({ categoryId: first.id, title: "First task", status: "ready" })
        Database.createTask({ categoryId: first.id, title: "Second task", status: "ready" })
        Database.createTask({ categoryId: second.id, title: "Third task", status: "ready" })

        board = createTemporaryObject(boardComponent, stage)
        verify(board !== null)
        wait(100)
    }

    function cleanup() {
        if (board) {
            board.destroy()
            board = null
        }
    }

    function test_categoryDragShowsMovingFullGroupGhost() {
        const categories = Database.listCategories()
        const firstCategory = categories[0]
        const secondCategory = categories[1]
        const handle = findChild(board, "category-drag-handle-" + firstCategory.id)
        const sourceSlot = findChild(board, "category-slot-" + firstCategory.id)
        const destinationSlot = findChild(board, "category-slot-" + secondCategory.id)
        const destinationDrop = findChild(board, "category-drop-target-" + secondCategory.id)
        const destinationAfterPlaceholder = findChild(board, "category-placeholder-after-" + secondCategory.id)
        const overlay = findChild(board, "drag-overlay")
        verify(handle !== null)
        verify(sourceSlot !== null)
        verify(destinationSlot !== null)
        verify(destinationDrop !== null)
        verify(destinationAfterPlaceholder !== null)
        verify(overlay !== null)

        board.beginCategoryDrag(firstCategory, handle, sourceSlot)
        compare(board.draggedCategoryId, firstCategory.id)
        verify(board.draggedCategoryId.length > 0)
        verify(!overlay.draggingTask)
        verify(overlay.sourceItem !== null)
        tryVerify(function() { return overlay.active }, 1000)
        verify(overlay.height > handle.height, "Category ghost must contain the full category group")
        verify(destinationDrop.height >= destinationSlot.height, "A category target must cover its full task group")
        const initialY = overlay.y

        handle.y += 80
        board.updateCategoryDragPosition(handle)
        tryVerify(function() { return Math.abs(overlay.y - initialY) > 20 }, 1000)

        const lowerHalfY = destinationDrop.height * 0.75
        compare(board.categoryGroupPlacement(lowerHalfY, destinationDrop.height, secondCategory.id), "after")
        board.previewCategoryMove(firstCategory.id, secondCategory.id, "after", destinationSlot)
        compare(board.draggedCategoryTargetId, secondCategory.id)
        compare(board.draggedCategoryPreviewItem, destinationSlot)
        compare(board.draggedCategoryPlacement, "after")
        tryVerify(function() { return destinationAfterPlaceholder.height > 0 }, 1000)
        compare(board.categoryGroupPlacement(lowerHalfY, destinationDrop.height, secondCategory.id), "after",
            "Placeholder expansion must not move the drop midpoint")

        board.commitCategoryDrop(firstCategory.id, secondCategory.id, board.draggedCategoryPlacement)
        board.finishCategoryDrag()
        tryVerify(function() { return !overlay.active }, 1000)
        const reorderedCategories = Database.listCategories()
        compare(reorderedCategories[0].id, secondCategory.id)
        compare(reorderedCategories[1].id, firstCategory.id)
    }
}
