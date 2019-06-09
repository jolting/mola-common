# ------------------------------------------------------------------------------
#        A Modular Optimization framework for Localization and mApping
#                               (MOLA)
#
# Copyright (C) 2018-2019, Jose Luis Blanco-Claraco, contributors (AUTHORS.md)
# All rights reserved.
# Released under GNU GPL v3. See LICENSE file
# ------------------------------------------------------------------------------

# This file defines utility CMake functions to ensure uniform settings all
# accross MOLA modules, programs, and tests.
# Usage:
#   include(mola_cmake_functions)
#
# Main functions (refer to their docs below)
#  - mola_add_library()
#  - mola_add_executable()
#


# Avoid the need for DLL export/import macros in Windows:
if (WIN32)
  set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS  ON)
endif()

# Detect wordsize:
if(CMAKE_SIZEOF_VOID_P EQUAL 8)  # Size in bytes!
  set(MOLA_WORD_SIZE 64)
else()
  set(MOLA_WORD_SIZE 32)
endif()

# Default output dirs for libs:
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY  "${CMAKE_BINARY_DIR}/lib/")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/")

# Compiler ID:
if (MSVC)
  # 1700 = VC 11.0 (2012)
  # 1800 = VC 12.0 (2013)
  #           ... (13 was skipped!)
  # 1900 = VC 14.0 (2015)
  # 1910 = VC 14.1 (2017)
  math(EXPR MSVC_VERSION_3D "(${MSVC_VERSION}/10)-60")
  if (MSVC_VERSION_3D GREATER 120)
    math(EXPR MSVC_VERSION_3D "${MSVC_VERSION_3D}+10")
  endif()
  set(MOLA_COMPILER_NAME "msvc${MSVC_VERSION_3D}")
else()
  set(MOLA_COMPILER_NAME "${CMAKE_CXX_COMPILER_ID}")
endif()

# Build DLL full name:
if (WIN32)
  set(MOLA_DLL_VERSION_POSTFIX
    "${MOLA_VERSION_NUMBER_MAJOR}${MOLA_VERSION_NUMBER_MINOR}${MOLA_VERSION_NUMBER_PATCH}_${MOLA_COMPILER_NAME}_x${MOLA_WORD_SIZE}")
  message(STATUS "Using DLL version postfix: ${MOLA_DLL_VERSION_POSTFIX}")
else()
  set(MOLA_DLL_VERSION_POSTFIX "")
endif()

# Group projects in "folders"
set_property(GLOBAL PROPERTY USE_FOLDERS ON)
set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "CMakeTargets")

# We want libraries to be named "libXXX" in all compilers, "libXXX-dbg" in MSVC
set(CMAKE_SHARED_LIBRARY_PREFIX "lib")
set(CMAKE_IMPORT_LIBRARY_PREFIX "lib")
set(CMAKE_STATIC_LIBRARY_PREFIX "lib")
set(CMAKE_DEBUG_POSTFIX "-dbg")

# -----------------------------------------------------------------------------
# mola_set_target_cxx17(target)
#
# Enabled C++17 for the given target
# -----------------------------------------------------------------------------
function(mola_set_target_cxx17 TARGETNAME)
  target_compile_features(${TARGETNAME} PUBLIC cxx_std_17)
  if (MSVC)
    # this seems to be required in addition to the cxx_std_17 above (?)
    target_compile_options(${TARGETNAME} PUBLIC /std:c++latest)
  endif()
endfunction()

# -----------------------------------------------------------------------------
# mola_set_target_build_options(target)
#
# Set defaults for each MOLA cmake target
# -----------------------------------------------------------------------------
function(mola_set_target_build_options TARGETNAME)
  # Build for C++17
  mola_set_target_cxx17(${TARGETNAME})

  # Warning level:
  if (MSVC)
    # msvc:
    target_compile_options(${TARGETNAME} PRIVATE /W3)
    target_compile_definitions(${TARGETNAME} PRIVATE
      _CRT_SECURE_NO_DEPRECATE
      _CRT_NONSTDC_NO_DEPRECATE
      _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS
    )
  else()
    # gcc & clang:
    target_compile_options(${TARGETNAME} PRIVATE
      -Wall -Wextra -Wshadow
      -Werror=return-type # error on missing return();
      -Wabi=11
      -Wtype-limits -Wcast-align -Wparentheses
      -fPIC
    )
  endif()

  # Optimization:
  # -------------------------
  if((NOT MSVC) AND (NOT CMAKE_CROSSCOMPILING))
    option(MOLA_BUILD_MARCH_NATIVE "Build with `-march=\"native\"`" ON)

    if (MOLA_BUILD_MARCH_NATIVE)
      # Note 1: GTSAM must be built with identical flags to avoid crashes.
      #  We will use this cmake variable too to populate GTSAM_BUILD_WITH_MARCH_NATIVE
      # Note 2: We must set "march=native" PUBLIC to avoid crashes with Eigen in derived projects
      target_compile_options(${TARGETNAME} PUBLIC -march=native)
    endif()

    if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
      target_compile_options(${TARGETNAME} PRIVATE -O3)
    endif()
  endif()

endfunction()

# -----------------------------------------------------------------------------
# mola_configure_library(target)
#
# Define a consistent install behavior for cmake-based library project:
# -----------------------------------------------------------------------------
function(mola_configure_library TARGETNAME)
  # Public hdrs interface:
  target_include_directories(${TARGETNAME} PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:include>
      PRIVATE src
    )

  # Dynamic libraries output options:
  # -----------------------------------
  set_target_properties(${TARGETNAME} PROPERTIES
    OUTPUT_NAME "${TARGETNAME}${MOLA_DLL_VERSION_POSTFIX}"
    COMPILE_PDB_NAME "${TARGETNAME}${MOLA_DLL_VERSION_POSTFIX}"
    COMPILE_PDB_NAME_DEBUG "${TARGETNAME}${MOLA_DLL_VERSION_POSTFIX}${CMAKE_DEBUG_POSTFIX}"
    VERSION "${MOLA_VERSION_NUMBER_MAJOR}.${MOLA_VERSION_NUMBER_MINOR}.${MOLA_VERSION_NUMBER_PATCH}"
    SOVERSION ${MOLA_VERSION_NUMBER_MAJOR}.${MOLA_VERSION_NUMBER_MINOR}
    )

  # Project "folder":
  # -------------------
  set_target_properties(${TARGETNAME} PROPERTIES FOLDER "MOLA-modules")

  # Install lib:
  install(TARGETS ${TARGETNAME} EXPORT ${TARGETNAME}-config
      ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
      LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
      RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )
  # Install hdrs:
  install(
    DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  )

  # Install cmake config module
  install(EXPORT ${TARGETNAME}-config DESTINATION share/${TARGETNAME}/cmake)

  # make project importable from build_dir:
  export(
    TARGETS ${TARGETNAME}
    FILE ${TARGETNAME}-config.cmake
  )

endfunction()

# -----------------------------------------------------------------------------
# mola_configure_app(target)
#
# Define common properties of cmake-based executable projects:
# -----------------------------------------------------------------------------
function(mola_configure_app TARGETNAME)
  # Project "folder":
  set_target_properties(${TARGETNAME} PROPERTIES FOLDER "MOLA-apps")

  #TODO: install?

endfunction()


# -----------------------------------------------------------------------------
# mola_add_library(
#	TARGET name
#	SOURCES ${SRC_FILES}
#	[PUBLIC_LINK_LIBRARIES lib1 lib2]
#	[PRIVATE_LINK_LIBRARIES lib3 lib4]
#	)
#
# Defines a MOLA library
# -----------------------------------------------------------------------------
function(mola_add_library)
    set(options "")
    set(oneValueArgs TARGET)
    set(multiValueArgs SOURCES PUBLIC_LINK_LIBRARIES PRIVATE_LINK_LIBRARIES)
    cmake_parse_arguments(MOLA_ADD_LIBRARY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    add_library(${MOLA_ADD_LIBRARY_TARGET}
	SHARED
	${MOLA_ADD_LIBRARY_SOURCES}
    )

    # Define common flags:
    mola_set_target_build_options(${MOLA_ADD_LIBRARY_TARGET})
    mola_configure_library(${MOLA_ADD_LIBRARY_TARGET})

    # lib Dependencies:
    target_link_libraries(${MOLA_ADD_LIBRARY_TARGET}
	    PUBLIC
	    ${MOLA_ADD_LIBRARY_PUBLIC_LINK_LIBRARIES}
    )
    target_link_libraries(${MOLA_ADD_LIBRARY_TARGET}
	    PRIVATE
	    ${MOLA_ADD_LIBRARY_PRIVATE_LINK_LIBRARIES}
    )
endfunction()

# -----------------------------------------------------------------------------
# mola_add_executable(
#	TARGET name
#	SOURCES ${SRC_FILES}
#	[LINK_LIBRARIES lib1 lib2]
#	)
#
# Defines a MOLA executable
# -----------------------------------------------------------------------------
function(mola_add_executable)
    set(options "")
    set(oneValueArgs TARGET)
    set(multiValueArgs SOURCES LINK_LIBRARIES)
    cmake_parse_arguments(MOLA_ADD_EXECUTABLE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    add_executable(${MOLA_ADD_EXECUTABLE_TARGET}
	    ${MOLA_ADD_EXECUTABLE_SOURCES}
    )

    # Define common flags:
    mola_set_target_build_options(${MOLA_ADD_EXECUTABLE_TARGET})
    mola_configure_app(${MOLA_ADD_EXECUTABLE_TARGET})

    # lib Dependencies:
    if (MOLA_ADD_EXECUTABLE_LINK_LIBRARIES)
	    target_link_libraries(
		    ${MOLA_ADD_EXECUTABLE_TARGET}
		    ${MOLA_ADD_EXECUTABLE_LINK_LIBRARIES}
	    )
    endif()
endfunction()
