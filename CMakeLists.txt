cmake_minimum_required(VERSION 3.21)

project(Workbench VERSION 0.1.0 LANGUAGES CXX)

option(WORKBENCH_ENABLE_COVERAGE "Instrument native targets for gcov-compatible coverage" OFF)
option(WORKBENCH_ENABLE_TEST_ADAPTERS "Compile test-only integration adapters into native modules" OFF)
if(WORKBENCH_ENABLE_COVERAGE)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        message(FATAL_ERROR "WORKBENCH_ENABLE_COVERAGE requires a GNU- or Clang-compatible compiler")
    endif()
    add_compile_options(-O0 -g --coverage)
    add_link_options(--coverage)
endif()

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
set(WORKBENCH_PLANE_QML_BUNDLE_DIR "${CMAKE_SOURCE_DIR}/package/contents/ui/plane")
set(WORKBENCH_PLANE_QML_BUILD_DIR "${CMAKE_BINARY_DIR}/qml/io/github/ownisticapps/workbench/plane")
set(WORKBENCH_PLASMOID_ARCHIVE "${CMAKE_BINARY_DIR}/plasma-workbench-${PROJECT_VERSION}.plasmoid")
set(WORKBENCH_PLASMOID_STAGING_DIR "${CMAKE_BINARY_DIR}/plasmoid-staging")
file(RELATIVE_PATH WORKBENCH_BUILD_DIR_RELATIVE "${CMAKE_SOURCE_DIR}" "${CMAKE_BINARY_DIR}")
# Keep the original package ID so an upgrade retains existing widgets and settings.
set(WORKBENCH_LEGACY_PLASMOID_ID "io.github.ownisticapps.worktodo")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${WORKBENCH_QML_BUNDLE_DIR}")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${WORKBENCH_PLANE_QML_BUNDLE_DIR}")
set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${WORKBENCH_PLASMOID_ARCHIVE}"
    "${WORKBENCH_PLASMOID_STAGING_DIR}"
)

add_subdirectory(src/time)
add_subdirectory(src/plane)

install(DIRECTORY package/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${WORKBENCH_LEGACY_PLASMOID_ID}
)
install(FILES LICENSE NOTICE SOURCE_OFFER.md THIRD_PARTY_NOTICES.md
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${WORKBENCH_LEGACY_PLASMOID_ID}
)
install(DIRECTORY LICENSES/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${WORKBENCH_LEGACY_PLASMOID_ID}/LICENSES
)
install(DIRECTORY ${CMAKE_SOURCE_DIR}/
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${WORKBENCH_LEGACY_PLASMOID_ID}/source
    PATTERN ".git" EXCLUDE
    PATTERN ".cortexkit" EXCLUDE
    PATTERN "build" EXCLUDE
    PATTERN "${WORKBENCH_BUILD_DIR_RELATIVE}" EXCLUDE
    REGEX "/package/contents/ui/time/" EXCLUDE
)

add_custom_target(package-plasmoid
    COMMAND ${CMAKE_COMMAND}
        -DPACKAGE_DIR=${CMAKE_SOURCE_DIR}/package
        -DSTAGING_DIR=${WORKBENCH_PLASMOID_STAGING_DIR}
        -DARCHIVE=${WORKBENCH_PLASMOID_ARCHIVE}
        -DLICENSE_FILE=${CMAKE_SOURCE_DIR}/LICENSE
        -DLICENSES_DIR=${CMAKE_SOURCE_DIR}/LICENSES
        -DNOTICE_FILE=${CMAKE_SOURCE_DIR}/NOTICE
        -DSOURCE_OFFER_FILE=${CMAKE_SOURCE_DIR}/SOURCE_OFFER.md
        -DTHIRD_PARTY_NOTICES_FILE=${CMAKE_SOURCE_DIR}/THIRD_PARTY_NOTICES.md
        -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
        -DBUILD_DIR=${CMAKE_BINARY_DIR}
        -P "${CMAKE_SOURCE_DIR}/cmake/PackagePlasmoid.cmake"
    DEPENDS
        workbench_timeplugin
        workbench_planeplugin
        "${CMAKE_SOURCE_DIR}/cmake/PackagePlasmoid.cmake"
        "${CMAKE_SOURCE_DIR}/LICENSE"
        "${CMAKE_SOURCE_DIR}/LICENSES/LGPL-3.0-or-later.txt"
        "${CMAKE_SOURCE_DIR}/NOTICE"
        "${CMAKE_SOURCE_DIR}/SOURCE_OFFER.md"
        "${CMAKE_SOURCE_DIR}/THIRD_PARTY_NOTICES.md"
    BYPRODUCTS "${WORKBENCH_PLASMOID_ARCHIVE}"
    COMMENT "Creating ${WORKBENCH_PLASMOID_ARCHIVE}"
    VERBATIM
)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests/time)
    add_subdirectory(tests/plane)
    add_subdirectory(tests/qml)
    add_subdirectory(tests/planning)
    add_subdirectory(tests/e2e)

    add_test(
        NAME plasmoid-cmake-install
        COMMAND ${CMAKE_COMMAND}
            -DBUILD_DIR=${CMAKE_BINARY_DIR}
            -DINSTALL_PREFIX=${CMAKE_BINARY_DIR}/plasmoid-cmake-install-test
            -DPLUGIN_ID=${WORKBENCH_LEGACY_PLASMOID_ID}
            -P "${CMAKE_SOURCE_DIR}/cmake/InstallPlasmoidCmakeSmokeTest.cmake"
    )
    set_tests_properties(plasmoid-cmake-install PROPERTIES LABELS packaging RUN_SERIAL TRUE)

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

    set_tests_properties(plasmoid-cmake-install PROPERTIES LABELS "fast;packaging")
    if(TEST plasmoid-archive-install)
        set_tests_properties(plasmoid-archive-install PROPERTIES LABELS "fast;packaging")
    endif()

    add_custom_target(fast-test
        COMMAND ${CMAKE_CTEST_COMMAND} --test-dir ${CMAKE_BINARY_DIR} -L fast --output-on-failure
        DEPENDS workbench_timeplugin workbench_planeplugin tst_timemath tst_planesync
        USES_TERMINAL
        COMMENT "Running the pull-request fast test gate"
    )
endif()
