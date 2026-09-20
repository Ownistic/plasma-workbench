add_executable(tst_planesync tst_planesync.cpp)
target_link_libraries(tst_planesync PRIVATE workbench_plane Qt6::Core Qt6::Test)
add_test(NAME PlaneSync COMMAND tst_planesync)
set_tests_properties(PlaneSync PROPERTIES LABELS "fast;unit")
