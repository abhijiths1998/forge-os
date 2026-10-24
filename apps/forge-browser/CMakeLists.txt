cmake_minimum_required(VERSION 3.21)
project(forge-browser VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Widgets Network WebEngineWidgets)

add_executable(forge-browser
  src/main.cpp
  src/adblock.cpp
  src/bookmarks.cpp
  src/browserwindow.cpp
  src/newtab.cpp
  src/tabsidebar.cpp
  src/webpage.cpp
  resources/resources.qrc
)
target_link_libraries(forge-browser PRIVATE
  Qt6::Widgets Qt6::Network Qt6::WebEngineWidgets)
target_compile_options(forge-browser PRIVATE -Wall -Wextra)

include(GNUInstallDirs)
install(TARGETS forge-browser RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/org.forgeos.browser.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
