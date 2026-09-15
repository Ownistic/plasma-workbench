cmake_minimum_required(VERSION 3.21)

foreach(required_variable IN ITEMS PACKAGE_DIR STAGING_DIR ARCHIVE)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "${required_variable} is required")
    endif()
endforeach()

# CMake's archive writer uses SOURCE_DATE_EPOCH for reproducible ZIP metadata.
file(REMOVE_RECURSE "${STAGING_DIR}")
file(MAKE_DIRECTORY "${STAGING_DIR}")
file(COPY "${PACKAGE_DIR}/" DESTINATION "${STAGING_DIR}")
file(GLOB_RECURSE archive_entries RELATIVE "${STAGING_DIR}" LIST_DIRECTORIES false "${STAGING_DIR}/*")

get_filename_component(archive_directory "${ARCHIVE}" DIRECTORY)
file(MAKE_DIRECTORY "${archive_directory}")
file(REMOVE "${ARCHIVE}")
set(ENV{SOURCE_DATE_EPOCH} "315532800")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${ARCHIVE}" --format=zip -- ${archive_entries}
    WORKING_DIRECTORY "${STAGING_DIR}"
    COMMAND_ERROR_IS_FATAL ANY
)
