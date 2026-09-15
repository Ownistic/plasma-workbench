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
set(WORKTODO_PLASMOID_ARCHIVE "${CMAKE_BINARY_DIR}/work-todo-${PROJECT_VERSION}.plasmoid")
set(WORKTODO_PLASMOID_STAGING_DIR "${CMAKE_BINARY_DIR}/plasmoid-staging")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${WORKTODO_QML_BUNDLE_DIR}")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${WORKTODO_PLASMOID_ARCHIVE}"
    "${WORKTODO_PLASMOID_STAGING_DIR}"
)

add_subdirectory(src/time)

install(DIRECTORY package/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/io.github.ownisticapps.worktodo
)

add_custom_target(package-plasmoid
    COMMAND ${CMAKE_COMMAND}
        -DPACKAGE_DIR=${CMAKE_SOURCE_DIR}/package
        -DSTAGING_DIR=${WORKTODO_PLASMOID_STAGING_DIR}
        -DARCHIVE=${WORKTODO_PLASMOID_ARCHIVE}
        -P "${CMAKE_SOURCE_DIR}/cmake/PackagePlasmoid.cmake"
    DEPENDS
        worktodo_timeplugin
        "${CMAKE_SOURCE_DIR}/cmake/PackagePlasmoid.cmake"
    BYPRODUCTS "${WORKTODO_PLASMOID_ARCHIVE}"
    COMMENT "Creating ${WORKTODO_PLASMOID_ARCHIVE}"
    VERBATIM
)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests/time)
    add_subdirectory(tests/qml)

    find_program(WORKTODO_KPACKAGETOOL_EXECUTABLE NAMES kpackagetool6)
    if(WORKTODO_KPACKAGETOOL_EXECUTABLE)
        add_test(
            NAME plasmoid-archive-install
            COMMAND ${CMAKE_COMMAND}
                -DKPACKAGE_TOOL=${WORKTODO_KPACKAGETOOL_EXECUTABLE}
                -DBUILD_DIR=${CMAKE_BINARY_DIR}
                -DARCHIVE=${WORKTODO_PLASMOID_ARCHIVE}
                -DPACKAGE_ROOT=${CMAKE_BINARY_DIR}/plasmoid-test-packages
                -DTEST_HOME=${CMAKE_BINARY_DIR}/plasmoid-test-home
                -DPLUGIN_ID=io.github.ownisticapps.worktodo
                -P "${CMAKE_SOURCE_DIR}/cmake/InstallPlasmoidArchiveSmokeTest.cmake"
        )
        set_tests_properties(plasmoid-archive-install PROPERTIES LABELS packaging RUN_SERIAL TRUE)
    endif()
endif()
