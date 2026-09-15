add_library(worktodo_time SHARED)

qt_add_qml_module(worktodo_time
    URI io.github.ownisticapps.worktodo.time
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/io/github/ownisticapps/worktodo/time"
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

install(TARGETS
    worktodo_time
    worktodo_timeplugin
    LIBRARY DESTINATION ${WORKTODO_QML_INSTALL_DIR}/io/github/ownisticapps/worktodo/time
)
install(FILES qmldir
    DESTINATION ${WORKTODO_QML_INSTALL_DIR}/io/github/ownisticapps/worktodo/time
)
