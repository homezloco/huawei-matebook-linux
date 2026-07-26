# FindMbedTLS.cmake — locate Mbed TLS using pkg-config so the upstream
# gxfp5130-linux userspace build works on Debian/Ubuntu systems that do not
# ship a MbedTLSConfig.cmake file.
#
# SPDX-License-Identifier: GPL-2.0
find_package(PkgConfig REQUIRED)
pkg_check_modules(PC_MbedTLS QUIET mbedtls)
pkg_check_modules(PC_MbedX509 QUIET mbedx509)
pkg_check_modules(PC_MbedCrypto QUIET mbedcrypto)

find_path(MbedTLS_INCLUDE_DIR
    NAMES mbedtls/ssl.h
    HINTS ${PC_MbedTLS_INCLUDE_DIRS}
)

find_library(MbedTLS_LIBRARY
    NAMES mbedtls
    HINTS ${PC_MbedTLS_LIBRARY_DIRS}
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(MbedTLS
    DEFAULT_MSG
    MbedTLS_LIBRARY
    MbedTLS_INCLUDE_DIR
)

if(MbedTLS_FOUND AND NOT TARGET MbedTLS::mbedtls)
    add_library(MbedTLS::mbedtls UNKNOWN IMPORTED)
    set(_mbedtls_link_libs "")
    list(APPEND _mbedtls_link_libs
        ${PC_MbedTLS_LIBRARIES}
        ${PC_MbedX509_LIBRARIES}
        ${PC_MbedCrypto_LIBRARIES}
    )
    set_target_properties(MbedTLS::mbedtls PROPERTIES
        IMPORTED_LOCATION "${MbedTLS_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${MbedTLS_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${_mbedtls_link_libs}"
    )
    unset(_mbedtls_link_libs)
endif()

mark_as_advanced(MbedTLS_INCLUDE_DIR MbedTLS_LIBRARY)
