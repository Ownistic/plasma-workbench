cmake_minimum_required(VERSION 3.21)

foreach(required_variable IN ITEMS KPACKAGE_TOOL BUILD_DIR ARCHIVE PACKAGE_ROOT TEST_HOME PLUGIN_ID)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "${required_variable} is required")
    endif()
endforeach()

execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${BUILD_DIR}" --target package-plasmoid
    COMMAND_ERROR_IS_FATAL ANY
)
if(NOT EXISTS "${ARCHIVE}")
    message(FATAL_ERROR "Release archive was not created: ${ARCHIVE}")
endif()

file(REMOVE_RECURSE "${PACKAGE_ROOT}" "${TEST_HOME}")
file(MAKE_DIRECTORY "${PACKAGE_ROOT}" "${TEST_HOME}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
        "HOME=${TEST_HOME}"
        "XDG_DATA_HOME=${TEST_HOME}/.local/share"
        "${KPACKAGE_TOOL}" --type Plasma/Applet --packageroot "${PACKAGE_ROOT}" --install "${ARCHIVE}"
    RESULT_VARIABLE install_result
    OUTPUT_VARIABLE install_output
    ERROR_VARIABLE install_error
)
if(NOT install_result EQUAL 0)
    message(FATAL_ERROR "kpackagetool6 install failed:\n${install_output}${install_error}")
endif()

set(installed_metadata "${PACKAGE_ROOT}/${PLUGIN_ID}/metadata.json")
if(NOT EXISTS "${installed_metadata}")
    message(FATAL_ERROR "Archive did not install ${installed_metadata}")
endif()
