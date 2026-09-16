add_library(workbench_time SHARED)

qt_add_qml_module(workbench_time
    URI io.github.ownisticapps.workbench.time
    VERSION 1.0
    OUTPUT_DIRECTORY "${WORKBENCH_QML_BUILD_DIR}"
    SOURCES
        timemath.cpp
        timemath.h
)

target_link_libraries(workbench_time
    PUBLIC
        Qt6::Core
        Qt6::Qml
)

target_include_directories(workbench_time
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

set_target_properties(workbench_time PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${WORKBENCH_QML_BUILD_DIR}"
)

# Both shared objects are shipped side-by-side in the plasmoid. Do not retain
# build-directory RPATH entries in the released plugin.
set_target_properties(workbench_time workbench_timeplugin PROPERTIES
    BUILD_RPATH_USE_ORIGIN TRUE
    INSTALL_RPATH "\$ORIGIN"
)

add_custom_command(TARGET workbench_timeplugin POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${WORKBENCH_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:workbench_time>" "${WORKBENCH_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:workbench_timeplugin>" "${WORKBENCH_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WORKBENCH_QML_BUILD_DIR}/qmldir" "${WORKBENCH_QML_BUNDLE_DIR}/qmldir"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WORKBENCH_QML_BUILD_DIR}/workbench_time.qmltypes" "${WORKBENCH_QML_BUNDLE_DIR}/workbench_time.qmltypes"
)
