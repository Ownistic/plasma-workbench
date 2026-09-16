cmake_minimum_required(VERSION 3.21)

foreach(required_variable IN ITEMS PACKAGE_DIR STAGING_DIR ARCHIVE LICENSE_FILE LICENSES_DIR NOTICE_FILE SOURCE_OFFER_FILE THIRD_PARTY_NOTICES_FILE SOURCE_DIR BUILD_DIR)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "${required_variable} is required")
    endif()
endforeach()

# CMake's archive writer uses SOURCE_DATE_EPOCH for reproducible ZIP metadata.
file(REMOVE_RECURSE "${STAGING_DIR}")
file(MAKE_DIRECTORY "${STAGING_DIR}")
file(COPY "${PACKAGE_DIR}/" DESTINATION "${STAGING_DIR}")
file(COPY "${LICENSE_FILE}" "${NOTICE_FILE}" "${SOURCE_OFFER_FILE}" "${THIRD_PARTY_NOTICES_FILE}" DESTINATION "${STAGING_DIR}")
file(COPY "${LICENSES_DIR}/" DESTINATION "${STAGING_DIR}/LICENSES")
file(RELATIVE_PATH build_dir_relative "${SOURCE_DIR}" "${BUILD_DIR}")
file(COPY "${SOURCE_DIR}/" DESTINATION "${STAGING_DIR}/source"
    PATTERN ".git" EXCLUDE
    PATTERN ".cortexkit" EXCLUDE
    PATTERN "build" EXCLUDE
    PATTERN "${build_dir_relative}" EXCLUDE
    REGEX "/package/contents/ui/time/" EXCLUDE
)
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
