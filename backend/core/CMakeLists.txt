cmake_minimum_required(VERSION 3.20)

project(voxon_core
  VERSION 0.1.0
  DESCRIPTION "Motor local de VOXON90: SQLite embebido y reglas del negocio"
  LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Tipo de compilación" FORCE)
endif()

option(VOXON_BUILD_TESTS "Compilar las pruebas del motor" ON)
option(VOXON_BUILD_JNI "Incluir el puente JNI para el servidor Java (si hay JDK)" ON)

set(VOXON_SQL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../sql/migrations")
find_package(Threads REQUIRED)

# --- SQLite embebido ----------------------------------------------------------
add_library(voxon_sqlite STATIC third_party/sqlite/sqlite3.c)
target_include_directories(voxon_sqlite SYSTEM PUBLIC third_party/sqlite)
target_compile_definitions(voxon_sqlite PUBLIC
  SQLITE_THREADSAFE=1
  SQLITE_DEFAULT_FOREIGN_KEYS=1
  SQLITE_DQS=0
  SQLITE_DEFAULT_MEMSTATUS=0
  SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_SHARED_CACHE
  SQLITE_ENABLE_MATH_FUNCTIONS)
if(MSVC)
  target_compile_options(voxon_sqlite PRIVATE /W0)
else()
  target_compile_options(voxon_sqlite PRIVATE -w)
endif()
target_link_libraries(voxon_sqlite PUBLIC Threads::Threads ${CMAKE_DL_LIBS})
if(UNIX AND NOT APPLE)
  target_link_libraries(voxon_sqlite PUBLIC m)
endif()

# --- Migraciones SQL incrustadas ---------------------------------------------
file(GLOB VOXON_MIGRATIONS CONFIGURE_DEPENDS "${VOXON_SQL_DIR}/*.sql")
list(SORT VOXON_MIGRATIONS)
string(REPLACE ";" "|" VOXON_MIGRATIONS_ARG "${VOXON_MIGRATIONS}")
set(VOXON_EMBEDDED_SQL "${CMAKE_CURRENT_BINARY_DIR}/generated/embedded_migrations.cpp")
add_custom_command(
  OUTPUT "${VOXON_EMBEDDED_SQL}"
  COMMAND "${CMAKE_COMMAND}" "-DOUTPUT=${VOXON_EMBEDDED_SQL}" "-DINPUTS=${VOXON_MIGRATIONS_ARG}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmbedSql.cmake"
  DEPENDS ${VOXON_MIGRATIONS} "${CMAKE_CURRENT_SOURCE_DIR}/cmake/EmbedSql.cmake"
  COMMENT "Incrustando migraciones SQL"
  VERBATIM)

# --- Advertencias para el código propio --------------------------------------
add_library(voxon_warnings INTERFACE)
if(MSVC)
  target_compile_options(voxon_warnings INTERFACE /W4 /permissive- /utf-8)
else()
  target_compile_options(voxon_warnings INTERFACE -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion)
endif()

# --- Motor (biblioteca estática) ---------------------------------------------
file(GLOB_RECURSE VOXON_ENGINE_SOURCES CONFIGURE_DEPENDS src/*.cpp)
list(FILTER VOXON_ENGINE_SOURCES EXCLUDE REGEX ".*/src/(c_api|jni_bridge)\\.cpp$")

add_library(voxon_engine STATIC ${VOXON_ENGINE_SOURCES} "${VOXON_EMBEDDED_SQL}")
target_include_directories(voxon_engine
  PUBLIC include
  PRIVATE src)
# <nlohmann/json.hpp>
target_include_directories(voxon_engine SYSTEM PUBLIC third_party)
target_link_libraries(voxon_engine PUBLIC voxon_sqlite PRIVATE voxon_warnings)
target_compile_definitions(voxon_engine PUBLIC VOXON_VERSION="${PROJECT_VERSION}")

# --- API en C (biblioteca compartida para FFI y JNI) --------------------------
add_library(voxoncore SHARED src/c_api.cpp)
target_link_libraries(voxoncore PRIVATE voxon_engine voxon_warnings)
target_include_directories(voxoncore PRIVATE src)
target_compile_definitions(voxoncore PRIVATE VOXON_BUILDING_SHARED)
set_target_properties(voxoncore PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  VERSION ${PROJECT_VERSION}
  SOVERSION ${PROJECT_VERSION_MAJOR})

if(VOXON_BUILD_JNI)
  set(VOXON_JAVA_HOME "$ENV{JAVA_HOME}")
  find_path(VOXON_JNI_INCLUDE jni.h HINTS "${VOXON_JAVA_HOME}/include")
  # Homebrew deja jni_md.h junto a jni.h; los JDK normales lo ponen en include/<sistema>.
  find_path(VOXON_JNI_MD_INCLUDE jni_md.h
    HINTS "${VOXON_JAVA_HOME}/include/darwin" "${VOXON_JAVA_HOME}/include/linux"
          "${VOXON_JAVA_HOME}/include/win32" "${VOXON_JAVA_HOME}/include")
  if(VOXON_JNI_INCLUDE AND VOXON_JNI_MD_INCLUDE)
    target_sources(voxoncore PRIVATE src/jni_bridge.cpp)
    target_include_directories(voxoncore SYSTEM PRIVATE "${VOXON_JNI_INCLUDE}" "${VOXON_JNI_MD_INCLUDE}")
    message(STATUS "VOXON: puente JNI incluido (${VOXON_JNI_INCLUDE})")
  else()
    message(STATUS "VOXON: sin JDK (JAVA_HOME); se omite el puente JNI")
  endif()
endif()

# --- Herramienta de línea de comandos ----------------------------------------
add_executable(voxon_cli tools/voxon_cli.cpp src/c_api.cpp)
target_link_libraries(voxon_cli PRIVATE voxon_engine voxon_warnings)
target_include_directories(voxon_cli PRIVATE src)
target_compile_definitions(voxon_cli PRIVATE VOXON_STATIC)

# --- Pruebas -----------------------------------------------------------------
if(VOXON_BUILD_TESTS)
  enable_testing()
  file(GLOB VOXON_TEST_SOURCES CONFIGURE_DEPENDS tests/*.cpp)
  add_executable(voxon_core_tests ${VOXON_TEST_SOURCES} src/c_api.cpp)
  target_link_libraries(voxon_core_tests PRIVATE voxon_engine voxon_warnings)
  target_include_directories(voxon_core_tests PRIVATE src)
  target_compile_definitions(voxon_core_tests PRIVATE VOXON_STATIC)
  add_test(NAME voxon_core_tests COMMAND voxon_core_tests)
endif()

# --- Instalación -------------------------------------------------------------
include(GNUInstallDirs)
install(TARGETS voxoncore voxon_cli
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(FILES include/voxon/voxon.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/voxon)
