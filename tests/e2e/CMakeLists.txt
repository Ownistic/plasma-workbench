# SPDX-FileCopyrightText: 2026 OwnisticApps
# SPDX-License-Identifier: LGPL-3.0-or-later

set(WORKBENCH_APPIUM_TEST "${CMAKE_CURRENT_SOURCE_DIR}/test_workbench.py")
set(WORKBENCH_APPIUM_ARTIFACTS "${CMAKE_BINARY_DIR}/appium-artifacts")

find_package(Python3 QUIET COMPONENTS Interpreter)
set(WORKBENCH_E2E_PYTHON_EXECUTABLE "${Python3_EXECUTABLE}")
find_package(SeleniumWebDriverATSPI QUIET)

if(WORKBENCH_E2E_PYTHON_EXECUTABLE)
    add_test(
        NAME AppiumTestSyntax
        COMMAND ${CMAKE_COMMAND} -E env
            PYTHONPYCACHEPREFIX=${CMAKE_BINARY_DIR}/python-cache
            ${WORKBENCH_E2E_PYTHON_EXECUTABLE} -m py_compile ${WORKBENCH_APPIUM_TEST}
    )
    set_tests_properties(AppiumTestSyntax PROPERTIES LABELS "e2e;static")
else()
    message(STATUS "Python3 not found; Appium test syntax check is not registered")
endif()

if(SeleniumWebDriverATSPI_FOUND AND WORKBENCH_E2E_PYTHON_EXECUTABLE)
    get_filename_component(WORKBENCH_E2E_PYTHON_BIN_DIR "${WORKBENCH_E2E_PYTHON_EXECUTABLE}" DIRECTORY)
    get_filename_component(WORKBENCH_E2E_DRIVER_BIN_DIR "${SELENIUM_WEBDRIVER_AT_SPI_RUN_PATH}" DIRECTORY)
    add_test(
        NAME WorkbenchAppiumE2E
        COMMAND ${SELENIUM_WEBDRIVER_AT_SPI_RUN_PATH}
            ${WORKBENCH_E2E_PYTHON_EXECUTABLE} ${WORKBENCH_APPIUM_TEST} --failfast
    )
    set_tests_properties(WorkbenchAppiumE2E PROPERTIES
        ENVIRONMENT
            "APPIUM_ARTIFACT_OUTPUT_PATH=${WORKBENCH_APPIUM_ARTIFACTS};COMPOSITOR_HEIGHT=900;COMPOSITOR_WIDTH=1280;PATH=${WORKBENCH_E2E_DRIVER_BIN_DIR}:${WORKBENCH_E2E_PYTHON_BIN_DIR}:$ENV{PATH};TEST_WITH_VIDEO_RECORDER=0;USE_CUSTOM_BUS=1;WORKBENCH_PACKAGE_DIR=${CMAKE_SOURCE_DIR}/package"
        LABELS "e2e"
        RESOURCE_LOCK workbench-appium
        TIMEOUT 240
    )

    add_custom_target(e2e
        COMMAND ${CMAKE_CTEST_COMMAND} --test-dir ${CMAKE_BINARY_DIR}
            -R "^WorkbenchAppiumE2E$" --output-on-failure
        DEPENDS workbench_timeplugin
        USES_TERMINAL
    )
elseif(NOT SeleniumWebDriverATSPI_FOUND)
    message(STATUS "SeleniumWebDriverATSPI not found; WorkbenchAppiumE2E is not registered")
else()
    message(STATUS "Python3 not found; WorkbenchAppiumE2E is not registered")
endif()
