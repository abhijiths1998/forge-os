#include "process.hpp"

#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <vector>

#include "util.hpp"

extern char** environ;

namespace fg {

SpawnResult spawnProcess(const LaunchSpec& spec, const std::string& logPath, bool detached) {
  SpawnResult res;
  if (spec.argv.empty()) { res.error = "empty command"; return res; }

  for (auto& d : spec.mkdirs) mkdirs(d);

  // Environment: current environ + overrides.
  std::vector<std::string> envStore;
  for (char** e = environ; e && *e; ++e) {
    std::string kv = *e;
    auto eq = kv.find('=');
    if (eq != std::string::npos && spec.env.count(kv.substr(0, eq))) continue;
    envStore.push_back(kv);
  }
  for (auto& [k, v] : spec.env) envStore.push_back(k + "=" + v);
  std::vector<char*> envp;
  for (auto& s : envStore) envp.push_back(const_cast<char*>(s.c_str()));
  envp.push_back(nullptr);
  std::vector<char*> argv;
  for (auto& s : spec.argv) argv.push_back(const_cast<char*>(s.c_str()));
  argv.push_back(nullptr);

  int logfd = -1;
  if (!detached && !logPath.empty()) {
    auto slash = logPath.rfind('/');
    if (slash != std::string::npos) mkdirs(logPath.substr(0, slash));
    logfd = ::open(logPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (logfd >= 0) {
      std::string head = "$";
      for (auto& a : spec.argv) head += " " + a;
      head += "\n";
      if (::write(logfd, head.data(), head.size()) < 0) { /* best effort */ }
    }
  }
  int nullfd = ::open("/dev/null", O_RDWR | O_CLOEXEC);

  int pfd[2];
  if (::pipe2(pfd, O_CLOEXEC) != 0) {
    res.error = std::string("pipe: ") + std::strerror(errno);
    if (logfd >= 0) ::close(logfd);
    if (nullfd >= 0) ::close(nullfd);
    return res;
  }

  pid_t pid = ::fork();
  if (pid < 0) {
    res.error = std::string("fork: ") + std::strerror(errno);
    ::close(pfd[0]); ::close(pfd[1]);
    if (logfd >= 0) ::close(logfd);
    if (nullfd >= 0) ::close(nullfd);
    return res;
  }
  if (pid == 0) {
    // child
    sigset_t empty;
    sigemptyset(&empty);
    sigprocmask(SIG_SETMASK, &empty, nullptr);
    signal(SIGPIPE, SIG_DFL);
    ::setsid();
    if (detached) {
      pid_t p2 = ::fork();
      if (p2 < 0) ::_exit(127);
      if (p2 > 0) ::_exit(0);
    }
    int out = logfd >= 0 ? logfd : nullfd;
    if (nullfd >= 0) ::dup2(nullfd, 0);
    if (out >= 0) { ::dup2(out, 1); ::dup2(out, 2); }
    if (!spec.workdir.empty() && ::chdir(spec.workdir.c_str()) != 0) {
      int e = errno;
      if (::write(pfd[1], &e, sizeof e) < 0) {}
      ::_exit(127);
    }
    ::execvpe(argv[0], argv.data(), envp.data());
    int e = errno;
    if (::write(pfd[1], &e, sizeof e) < 0) {}
    ::_exit(127);
  }

  // parent
  ::close(pfd[1]);
  if (logfd >= 0) ::close(logfd);
  if (nullfd >= 0) ::close(nullfd);
  if (detached) {
    int st = 0;
    while (::waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
  }
  int childErr = 0;
  ssize_t n;
  do { n = ::read(pfd[0], &childErr, sizeof childErr); } while (n < 0 && errno == EINTR);
  ::close(pfd[0]);
  if (n == static_cast<ssize_t>(sizeof childErr)) {
    if (!detached) {
      int st = 0;
      while (::waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    }
    res.error = spec.argv[0] + ": " + std::strerror(childErr);
    return res;
  }
  res.ok = true;
  res.pid = detached ? 0 : pid;
  return res;
}

}  // namespace fg
