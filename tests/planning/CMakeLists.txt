find_package(Python3 REQUIRED COMPONENTS Interpreter)

add_test(
    NAME TestCoverageMatrix
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_SOURCE_DIR}/scripts/validate-test-matrix.py
        --prd ${CMAKE_SOURCE_DIR}/PRD.md
        --matrix ${CMAKE_SOURCE_DIR}/docs/planning/TEST_COVERAGE_MATRIX.md
)
set_tests_properties(TestCoverageMatrix PROPERTIES LABELS "fast;static")
