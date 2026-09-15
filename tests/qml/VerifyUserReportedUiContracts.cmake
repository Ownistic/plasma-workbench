if(NOT DEFINED SOURCE_DIR)
    message(FATAL_ERROR "SOURCE_DIR is required")
endif()

function(read_source relative_path output_variable)
    file(READ "${SOURCE_DIR}/${relative_path}" source)
    set(${output_variable} "${source}" PARENT_SCOPE)
endfunction()

read_source("package/contents/ui/TodoBoard.qml" todo_board)
read_source("package/contents/ui/TaskCard.qml" task_card)
read_source("package/contents/ui/TaskDetails.qml" task_details)
read_source("package/contents/ui/ReportsView.qml" reports_view)

# Dialog enum assignments caused the widget to fail loading before any action
# could be used. Zero is not a valid QML enum assignment for standardButtons.
foreach(source IN ITEMS "${todo_board}" "${task_details}" "${reports_view}")
    if(source MATCHES "standardButtons:[ \t]*0")
        message(FATAL_ERROR "Dialogs must omit standardButtons when no standard button is required")
    endif()
endforeach()

# Popups in a plasmoid need an explicit visual parent; ApplicationWindow's
# implicit overlay is unavailable in this component hierarchy.
if(todo_board MATCHES "Controls\\.Dialog[^{]*\\{[^}]*parent:[ \t]*root\\.parent")
    message(FATAL_ERROR "TodoBoard dialogs must be parented to TodoBoard")
endif()
if(task_details MATCHES "parent:[ \t]*root\\.parent" OR reports_view MATCHES "parent:[ \t]*root\\.parent")
    message(FATAL_ERROR "Nested dialogs must not rely on a parent dialog's QObject parent")
endif()
if(NOT task_details MATCHES "parent:[ \t]*root\\.contentItem" OR NOT reports_view MATCHES "parent:[ \t]*root\\.contentItem")
    message(FATAL_ERROR "Nested dialogs must use their owning dialog's QQuickItem content parent")
endif()
if(NOT task_details MATCHES "parent:[ \t]*root\\.board" OR NOT reports_view MATCHES "parent:[ \t]*root\\.board")
    message(FATAL_ERROR "Top-level details and report dialogs must be parented to TodoBoard")
endif()

# TaskDetails is a separate component, so it cannot access TodoBoard's private
# ListModel ID. Keep the explicit public alias and consume that API.
if(NOT todo_board MATCHES "property alias categories:[ \t]*categoryModel")
    message(FATAL_ERROR "TodoBoard must expose its category model to TaskDetails")
endif()
if(task_details MATCHES "board\\.categoryModel" OR NOT task_details MATCHES "board\\.categories")
    message(FATAL_ERROR "TaskDetails must use TodoBoard's public categories model")
endif()

# A root-level TapHandler swallowed edit and overflow button clicks. Details
# taps belong only to the task information column, while the menu is anchored.
if(NOT task_card MATCHES "onTapped:[ \t]*root\\.openRequested\\(\\)")
    message(FATAL_ERROR "Task information must retain a details-open tap handler")
endif()
if(NOT task_card MATCHES "taskActionsMenu\\.popup\\(taskActionsButton, 0, taskActionsButton\\.height\\)")
    message(FATAL_ERROR "Task action menu must be anchored to its button")
endif()
