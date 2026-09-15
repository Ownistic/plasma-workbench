add_library(worktodo_time SHARED)

qt_add_qml_module(worktodo_time
    URI io.github.ownisticapps.worktodo.time
    VERSION 1.0
    OUTPUT_DIRECTORY "${WORKTODO_QML_BUILD_DIR}"
    SOURCES
        timemath.cpp
        timemath.h
)

target_link_libraries(worktodo_time
    PUBLIC
        Qt6::Core
        Qt6::Qml
)

target_include_directories(worktodo_time
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
)

set_target_properties(worktodo_time PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${WORKTODO_QML_BUILD_DIR}"
)

# Both shared objects are shipped side-by-side in the plasmoid. Do not retain
# build-directory RPATH entries in the released plugin.
set_target_properties(worktodo_time worktodo_timeplugin PROPERTIES
    BUILD_RPATH_USE_ORIGIN TRUE
    INSTALL_RPATH "\$ORIGIN"
)

add_custom_command(TARGET worktodo_timeplugin POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${WORKTODO_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:worktodo_time>" "${WORKTODO_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:worktodo_timeplugin>" "${WORKTODO_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WORKTODO_QML_BUILD_DIR}/qmldir" "${WORKTODO_QML_BUNDLE_DIR}/qmldir"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WORKTODO_QML_BUILD_DIR}/worktodo_time.qmltypes" "${WORKTODO_QML_BUNDLE_DIR}/worktodo_time.qmltypes"
)
