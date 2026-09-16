add_executable(tst_timemath
    tst_timemath.cpp
)

target_link_libraries(tst_timemath
    PRIVATE
        workbench_time
        Qt6::Core
        Qt6::Test
)

add_test(NAME TimeMath COMMAND tst_timemath)
