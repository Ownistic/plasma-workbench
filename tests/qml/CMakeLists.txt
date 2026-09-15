find_program(QMLTESTRUNNER
    NAMES qmltestrunner
    HINTS /usr/lib/qt6/bin
    REQUIRED
)

add_test(
    NAME DatabaseRepository
    COMMAND ${QMLTESTRUNNER} -import ${CMAKE_BINARY_DIR}/qml -input ${CMAKE_CURRENT_SOURCE_DIR}
)
set_tests_properties(DatabaseRepository PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
)
