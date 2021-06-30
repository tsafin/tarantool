macro(libccdt_build)
    set(LIBCDT_INCLUDE_DIRS ${PROJECT_SOURCE_DIR}/third_party/c-dt/)
    set(LIBCDT_LIBRARIES cdt)

    file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/third_party/c-dt/build/)
    add_subdirectory(${PROJECT_SOURCE_DIR}/third_party/c-dt
                     ${CMAKE_CURRENT_BINARY_DIR}/third_party/c-dt/build/)
endmacro()
