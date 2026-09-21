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
find_program(XVFB_RUN NAMES xvfb-run)

set(QML_TEST_COMMAND ${QMLTESTRUNNER})
set(QML_TEST_ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_DATA_HOME=${CMAKE_BINARY_DIR}/test-data")
if(XVFB_RUN)
    set(QML_TEST_COMMAND ${XVFB_RUN} -a ${QMLTESTRUNNER})
    set(QML_TEST_ENVIRONMENT "XDG_DATA_HOME=${CMAKE_BINARY_DIR}/test-data")
endif()

add_test(
    NAME DatabaseRepository
    COMMAND ${QML_TEST_COMMAND} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}
)
set_tests_properties(DatabaseRepository PROPERTIES
    ENVIRONMENT "${QML_TEST_ENVIRONMENT}"
    LABELS "fast;integration;qml"
    TIMEOUT 120
)

add_test(
    NAME CategoryDragE2E
    COMMAND ${QML_TEST_COMMAND} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}/tst_category_drag.qml
)
set_tests_properties(CategoryDragE2E PROPERTIES
    ENVIRONMENT "${QML_TEST_ENVIRONMENT}"
    LABELS "fast;integration;qml"
    TIMEOUT 120
)

add_test(
    NAME UserReportedUiQmlSyntax
    COMMAND ${QMLLINT} -I ${CMAKE_BINARY_DIR}/qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/main.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/TodoBoard.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/CategoryDragGroup.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/CategoryHeader.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/TaskCard.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/TaskDetails.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/PlaneIntegration.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/PlaneSettings.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/PlaneOwnerPicker.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/SettingsPage.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/WorkbenchSettingsPage.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/WorkflowStatusSettings.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/ReportsView.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/DailyTimeline.qml
        ${CMAKE_SOURCE_DIR}/package/contents/ui/YearHeatmap.qml
)
set_tests_properties(UserReportedUiQmlSyntax PROPERTIES LABELS "fast;static;qml")

add_test(
    NAME UserReportedUiContracts
    COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/VerifyUserReportedUiContracts.cmake
)
set_tests_properties(UserReportedUiContracts PROPERTIES LABELS "fast;static;qml")

add_test(
    NAME RepositoryBenchmark
    COMMAND ${QML_TEST_COMMAND} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}/../benchmark
)
set_tests_properties(RepositoryBenchmark PROPERTIES
    DISABLED TRUE
    ENVIRONMENT "${QML_TEST_ENVIRONMENT}"
    LABELS benchmark
)

add_custom_target(benchmark-repository
    COMMAND ${QMLTESTRUNNER} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}/../benchmark
    DEPENDS workbench_timeplugin
    COMMENT "Benchmarking 5,000 tasks and 100,000 work sessions"
    VERBATIM
)
