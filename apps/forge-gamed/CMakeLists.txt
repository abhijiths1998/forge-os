cmake_minimum_required(VERSION 3.20)
project(forge-gamed VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(PkgConfig REQUIRED)
find_package(SDL3 REQUIRED CONFIG)
pkg_check_modules(JSONCPP REQUIRED IMPORTED_TARGET jsoncpp)
pkg_check_modules(SQLITE3 REQUIRED IMPORTED_TARGET sqlite3)
pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl)

add_library(forgegamed_core STATIC
  src/util.cpp
  src/vdf.cpp
  src/model.cpp
  src/store.cpp
  src/scan.cpp
  src/launch.cpp
  src/runners.cpp
  src/padnav.cpp
  src/pads.cpp
  src/process.cpp
  src/watch.cpp
  src/profile.cpp
  src/daemon.cpp
  src/client.cpp)
target_include_directories(forgegamed_core PUBLIC src)
target_compile_options(forgegamed_core PUBLIC -Wall -Wextra)
target_compile_definitions(forgegamed_core PUBLIC FORGE_GAMED_VERSION="${PROJECT_VERSION}")
target_link_libraries(forgegamed_core PUBLIC SDL3::SDL3 PkgConfig::JSONCPP PkgConfig::SQLITE3 PkgConfig::CURL pthread)

add_executable(forge-gamed src/main.cpp)
target_link_libraries(forge-gamed PRIVATE forgegamed_core)

enable_testing()
add_executable(forge-gamed-tests tests/tests.cpp)
target_link_libraries(forge-gamed-tests PRIVATE forgegamed_core)
add_test(NAME forge-gamed-tests COMMAND forge-gamed-tests)

install(TARGETS forge-gamed RUNTIME DESTINATION bin)
install(FILES data/forge-gamed.service DESTINATION lib/systemd/user)
