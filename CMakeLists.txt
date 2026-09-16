cmake_minimum_required(VERSION 3.21)

project(Workbench VERSION 0.1.0 LANGUAGES CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

find_package(Qt6 6.7 REQUIRED COMPONENTS Core Qml Test)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

# The compiled module is bundled with the plasmoid so kpackagetool can install
# one self-contained package. CMake writes its runtime artifacts here on build.
set(WORKBENCH_QML_BUNDLE_DIR "${CMAKE_SOURCE_DIR}/package/contents/ui/time")
set(WORKBENCH_QML_BUILD_DIR "${CMAKE_BINARY_DIR}/qml/io/github/ownisticapps/workbench/time")
set(WORKBENCH_PLASMOID_ARCHIVE "${CMAKE_BINARY_DIR}/plasma-workbench-${PROJECT_VERSION}.plasmoid")
set(WORKBENCH_PLASMOID_STAGING_DIR "${CMAKE_BINARY_DIR}/plasmoid-staging")
# Keep the original package ID so an upgrade retains existing widgets and settings.
set(WORKBENCH_LEGACY_PLASMOID_ID "io.github.ownisticapps.worktodo")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${WORKBENCH_QML_BUNDLE_DIR}")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${WORKBENCH_PLASMOID_ARCHIVE}"
    "${WORKBENCH_PLASMOID_STAGING_DIR}"
)

add_subdirectory(src/time)

install(DIRECTORY package/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${WORKBENCH_LEGACY_PLASMOID_ID}
)

add_custom_target(package-plasmoid
    COMMAND ${CMAKE_COMMAND}
        -DPACKAGE_DIR=${CMAKE_SOURCE_DIR}/package
        -DSTAGING_DIR=${WORKBENCH_PLASMOID_STAGING_DIR}
        -DARCHIVE=${WORKBENCH_PLASMOID_ARCHIVE}
        -P "${CMAKE_SOURCE_DIR}/cmake/PackagePlasmoid.cmake"
    DEPENDS
        workbench_timeplugin
        "${CMAKE_SOURCE_DIR}/cmake/PackagePlasmoid.cmake"
    BYPRODUCTS "${WORKBENCH_PLASMOID_ARCHIVE}"
    COMMENT "Creating ${WORKBENCH_PLASMOID_ARCHIVE}"
    VERBATIM
)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests/time)
    add_subdirectory(tests/qml)

    find_program(WORKBENCH_KPACKAGETOOL_EXECUTABLE NAMES kpackagetool6)
    if(WORKBENCH_KPACKAGETOOL_EXECUTABLE)
        add_test(
            NAME plasmoid-archive-install
            COMMAND ${CMAKE_COMMAND}
                -DKPACKAGE_TOOL=${WORKBENCH_KPACKAGETOOL_EXECUTABLE}
                -DBUILD_DIR=${CMAKE_BINARY_DIR}
                -DARCHIVE=${WORKBENCH_PLASMOID_ARCHIVE}
                -DPACKAGE_ROOT=${CMAKE_BINARY_DIR}/plasmoid-test-packages
                -DTEST_HOME=${CMAKE_BINARY_DIR}/plasmoid-test-home
                -DPLUGIN_ID=${WORKBENCH_LEGACY_PLASMOID_ID}
                -P "${CMAKE_SOURCE_DIR}/cmake/InstallPlasmoidArchiveSmokeTest.cmake"
        )
        set_tests_properties(plasmoid-archive-install PROPERTIES LABELS packaging RUN_SERIAL TRUE)
    endif()
endif()
