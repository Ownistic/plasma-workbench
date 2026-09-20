find_package(Qt6 6.7 REQUIRED COMPONENTS Network)
find_package(KF6Wallet QUIET)

add_library(workbench_plane SHARED)

qt_add_qml_module(workbench_plane
    URI io.github.ownisticapps.workbench.plane
    VERSION 1.0
    OUTPUT_DIRECTORY "${WORKBENCH_PLANE_QML_BUILD_DIR}"
    SOURCES
        planesync.cpp
        planesync.h
)

target_link_libraries(workbench_plane
    PUBLIC
        Qt6::Core
        Qt6::Network
        Qt6::Qml
)

if(TARGET KF6::Wallet)
    target_link_libraries(workbench_plane PRIVATE KF6::Wallet)
    target_compile_definitions(workbench_plane PRIVATE WORKBENCH_HAVE_KWALLET=1)
endif()

target_include_directories(workbench_plane PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
set_target_properties(workbench_plane PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${WORKBENCH_PLANE_QML_BUILD_DIR}"
)

# The plane module is optional at configure time but self-contained when built.
set_target_properties(workbench_plane workbench_planeplugin PROPERTIES
    BUILD_RPATH_USE_ORIGIN TRUE
    INSTALL_RPATH "\$ORIGIN"
)

add_custom_command(TARGET workbench_planeplugin POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${WORKBENCH_PLANE_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:workbench_plane>" "${WORKBENCH_PLANE_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:workbench_planeplugin>" "${WORKBENCH_PLANE_QML_BUNDLE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WORKBENCH_PLANE_QML_BUILD_DIR}/qmldir" "${WORKBENCH_PLANE_QML_BUNDLE_DIR}/qmldir"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WORKBENCH_PLANE_QML_BUILD_DIR}/workbench_plane.qmltypes" "${WORKBENCH_PLANE_QML_BUNDLE_DIR}/workbench_plane.qmltypes"
)
