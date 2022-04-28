add_library(tzcode STATIC strftime.c strptime.c timelocal.c timezone.c)
target_link_libraries(tzcode)

set(TZCODE_PROJECT tzcode-github)
set(TZCODE_BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR})
set(TZCODE_PREFIX ${TZCODE_BUILD_DIR}/tz)
set(TZDATA_TARGETS
    ${TZCODE_PREFIX}/src/${TZCODE_PROJECT}/main.zi
)

ExternalProject_Add(${TZCODE_PROJECT}
    GIT_REPOSITORY https://github.com/eggert/tz
    GIT_TAG 2022a
    GIT_SHALLOW YES

    INSTALL_DIR ${TZCODE_BUILD_DIR}/install
    PREFIX 

    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ""

    BUILD_COMMAND ${CMAKE_COMMAND} -E env
        CC=${CMAKE_C_COMPILER}
        CFLAGS=${CMAKE_C_FLAGS}
        PACKRATDATA=backzone
        make -C <SOURCE_DIR> ${TZDATA_TARGETS}
    BUILD_IN_SOURCE TRUE
    TEST_COMMAND ""
    INSTALL_COMMAND make DESTDIR=<INSTALL_DIR> install
    BUILD_BYPRODUCTS ${TZDATA_TARGETS}
)
