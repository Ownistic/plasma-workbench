find_program(QMLTESTRUNNER
    NAMES qmltestrunner
    HINTS /usr/lib/qt6/bin
    REQUIRED
)
find_program(QMLLINT
    NAMES qmllint
    HINTS /usr/lib/qt6/bin
    REQUIRED
)

add_test(
    NAME DatabaseRepository
    COMMAND ${QMLTESTRUNNER} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}
)
set_tests_properties(DatabaseRepository PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
)

add_test(
    NAME CategoryDragE2E
    COMMAND ${QMLTESTRUNNER} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}/tst_category_drag.qml
)
set_tests_properties(CategoryDragE2E PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
)

add_test(
    NAME UserReportedUiQmlSyntax
    COMMAND ${QMLLINT} -I ${CMAKE_BINARY_DIR}/qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/main.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/TodoBoard.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/TaskCard.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/TaskDetails.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/ReportsView.qml
)

add_test(
    NAME UserReportedUiContracts
    COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/VerifyUserReportedUiContracts.cmake
)

add_custom_target(benchmark-repository
    COMMAND ${QMLTESTRUNNER} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}/../benchmark
    DEPENDS worktodo_timeplugin
    COMMENT "Benchmarking 5,000 tasks and 100,000 work sessions"
    VERBATIM
)
