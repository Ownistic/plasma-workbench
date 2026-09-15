cmake_minimum_required(VERSION 3.21)

project(WorkTodo VERSION 0.1.0 LANGUAGES CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

find_package(Qt6 6.7 REQUIRED COMPONENTS Core Qml Test)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

set(WORKTODO_QML_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/qt6/qml")

add_subdirectory(src/time)

install(DIRECTORY package/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/io.github.ownisticapps.worktodo
)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests/time)
    add_subdirectory(tests/qml)
endif()
