cmake_minimum_required(VERSION 3.21)

foreach(required_variable IN ITEMS BUILD_DIR INSTALL_PREFIX PLUGIN_ID)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "${required_variable} is required")
    endif()
endforeach()

execute_process(
    COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}" --prefix "${INSTALL_PREFIX}"
    COMMAND_ERROR_IS_FATAL ANY
)

foreach(required_file IN ITEMS
    LICENSE
    NOTICE
    SOURCE_OFFER.md
    THIRD_PARTY_NOTICES.md
    LICENSES/LGPL-3.0-or-later.txt
    source/CMakeLists.txt
    source/src/time/timemath.cpp
)
    if(NOT EXISTS "${INSTALL_PREFIX}/share/plasma/plasmoids/${PLUGIN_ID}/${required_file}")
        message(FATAL_ERROR "CMake install did not include required compliance file ${required_file}")
    endif()
endforeach()
