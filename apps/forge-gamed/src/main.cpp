#include <cstdio>
#include <cstring>
#include <iostream>

#include "client.hpp"
#include "daemon.hpp"

static void usage() {
  std::cout << "forge-gamed " FORGE_GAMED_VERSION " - Forge Gaming daemon\n"
               "usage:\n"
               "  forge-gamed                        run the daemon\n"
               "  forge-gamed --call <method> [json] send one request, print the response\n"
               "  forge-gamed --watch                print daemon events\n"
               "  forge-gamed --version | --help\n";
}

int main(int argc, char** argv) {
  if (argc >= 2) {
    std::string a = argv[1];
    if (a == "--version" || a == "-V") {
      std::cout << "forge-gamed " FORGE_GAMED_VERSION "\n";
      return 0;
    }
    if (a == "--help" || a == "-h") {
      usage();
      return 0;
    }
    if (a == "--call") {
      if (argc < 3) {
        usage();
        return 2;
      }
      return fg::cmdCall(argv[2], argc >= 4 ? argv[3] : "");
    }
    if (a == "--watch") return fg::cmdWatch();
    std::cerr << "forge-gamed: unknown option " << a << "\n";
    usage();
    return 2;
  }
  fg::Daemon d;
  return d.run();
}
