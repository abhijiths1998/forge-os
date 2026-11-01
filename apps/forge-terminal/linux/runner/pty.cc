// The terminal's pseudo-terminals, for lib/pty.dart (dart:ffi looks these
// up in the executable itself, which is linked with ENABLE_EXPORTS).
//
// Forking has to happen here, in C: the child of a fork in the Dart VM
// would run Dart on a copy of a multi-threaded process. The child only
// does what's safe after fork() before execve().
#include <errno.h>
#include <fcntl.h>
#include <pty.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define FORGE_EXPORT extern "C" __attribute__((visibility("default"), used))

// Start `file` (found in PATH like execvp) with `argv` and the environment
// `envp` in `cwd` on a new pseudo-terminal of rows x cols. Returns the
// child's pid and puts the terminal's master end in *master; -1 on failure.
FORGE_EXPORT int forge_pty_spawn(const char* file, char* const* argv,
                                 char* const* envp, const char* cwd, int rows,
                                 int cols, int* master) {
  struct winsize size = {};
  size.ws_row = rows > 0 ? rows : 24;
  size.ws_col = cols > 0 ? cols : 80;

  struct termios tio = {};
  int fd = -1;
  // Sane defaults (a login terminal's): UTF-8 input, ^C/^Z/^\ signals,
  // erase on DEL like every terminal today.
  tio.c_iflag = ICRNL | IXON | IUTF8;
  tio.c_oflag = OPOST | ONLCR;
  tio.c_cflag = CREAD | CS8 | HUPCL;
  tio.c_lflag = ISIG | ICANON | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;
  tio.c_cc[VINTR] = 0x03;
  tio.c_cc[VQUIT] = 0x1c;
  tio.c_cc[VERASE] = 0x7f;
  tio.c_cc[VKILL] = 0x15;
  tio.c_cc[VEOF] = 0x04;
  tio.c_cc[VSTART] = 0x11;
  tio.c_cc[VSTOP] = 0x13;
  tio.c_cc[VSUSP] = 0x1a;
  tio.c_cc[VWERASE] = 0x17;
  tio.c_cc[VLNEXT] = 0x16;
  tio.c_cc[VREPRINT] = 0x12;
  tio.c_cc[VMIN] = 1;
  tio.c_cc[VTIME] = 0;
  cfsetispeed(&tio, B38400);
  cfsetospeed(&tio, B38400);

  pid_t pid = forkpty(&fd, nullptr, &tio, &size);
  if (pid < 0) return -1;
  if (pid == 0) {
    // The child: a clean slate of signals (GTK and the engine block and
    // ignore some, which the shell would inherit), none of our files.
    sigset_t all;
    sigemptyset(&all);
    sigprocmask(SIG_SETMASK, &all, nullptr);
    for (int s = 1; s < NSIG; s++) signal(s, SIG_DFL);
    close_range(3, ~0U, 0);
    if (cwd != nullptr && cwd[0] != '\0' && chdir(cwd) != 0) {
      if (chdir(getenv("HOME") ? getenv("HOME") : "/") != 0) {
        // Stay where we are.
      }
    }
    execvpe(file, argv, envp);
    // The program isn't there: say so on the terminal, then end.
    const char* msg = "forge-terminal: can't run ";
    if (write(2, msg, strlen(msg)) < 0 || write(2, file, strlen(file)) < 0 ||
        write(2, "\r\n", 2) < 0) {
    }
    _exit(127);
  }
  fcntl(fd, F_SETFD, FD_CLOEXEC);
  *master = fd;
  return pid;
}

FORGE_EXPORT int forge_pty_resize(int fd, int rows, int cols, int width,
                                  int height) {
  struct winsize size = {};
  size.ws_row = rows;
  size.ws_col = cols;
  size.ws_xpixel = width;
  size.ws_ypixel = height;
  return ioctl(fd, TIOCSWINSZ, &size);
}

// Blocks until there's output; 0 once the terminal is gone (the program
// and everything it started ended, which Linux reports as EIO).
FORGE_EXPORT int forge_pty_read(int fd, uint8_t* buf, int len) {
  for (;;) {
    ssize_t n = read(fd, buf, len);
    if (n >= 0) return (int)n;
    if (errno == EINTR || errno == EAGAIN) continue;
    return 0;
  }
}

FORGE_EXPORT int forge_pty_write(int fd, const uint8_t* buf, int len) {
  int done = 0;
  while (done < len) {
    ssize_t n = write(fd, buf + done, len - done);
    if (n < 0) {
      if (errno == EINTR || errno == EAGAIN) continue;
      return -1;
    }
    done += (int)n;
  }
  return done;
}

// The program's exit status (128 + signal if it was killed).
FORGE_EXPORT int forge_pty_wait(int pid) {
  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) return -1;
  }
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return -1;
}

// The process group in the terminal's foreground (the shell, or what it's
// running), for the tab's title and for "open a new tab here".
FORGE_EXPORT int forge_pty_foreground(int fd) { return tcgetpgrp(fd); }

FORGE_EXPORT int forge_pty_close(int fd, int pid) {
  if (pid > 0) kill(pid, SIGHUP);
  return close(fd);
}
