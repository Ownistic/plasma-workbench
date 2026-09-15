cmake_minimum_required(VERSION 3.21)

project(WorkTodo VERSION 0.1.0 LANGUAGES CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

find_package(Qt6 6.7 REQUIRED COMPONENTS Core Qml Test)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

# The compiled module is bundled with the plasmoid so kpackagetool can install
# one self-contained package. CMake writes its runtime artifacts here on build.
set(WORKTODO_QML_BUNDLE_DIR "${CMAKE_SOURCE_DIR}/package/contents/ui/time")
set(WORKTODO_QML_BUILD_DIR "${CMAKE_BINARY_DIR}/qml/io/github/ownisticapps/worktodo/time")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${WORKTODO_QML_BUNDLE_DIR}")

add_subdirectory(src/time)

install(DIRECTORY package/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/io.github.ownisticapps.worktodo
)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests/time)
    add_subdirectory(tests/qml)
endif()
