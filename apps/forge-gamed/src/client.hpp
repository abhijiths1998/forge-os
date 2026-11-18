#pragma once
#include <string>

namespace fg {

// --call: sends one request, prints the response line. Exit code 1 on an
// error response or connection failure.
int cmdCall(const std::string& method, const std::string& paramsJson);
// --watch: prints events until the connection closes or Ctrl-C. Existing pads
// are printed first as synthetic pad.connected events.
int cmdWatch();

}  // namespace fg
