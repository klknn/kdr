// -*- mode: d; c-basic-offset: 2 -*-
module kdr.logging;

import core.thread.types : ThreadID;
import core.stdc.stdio : fprintf, fputc, stderr;
import core.stdc.time : tm;
import std.datetime.systime : Clock, SysTime;

import dplug.core.nogc : assumeNothrowNoGC;
import dplug.core.sync : UncheckedMutex;

private ThreadID _thisThreadID() @trusted @nogc nothrow {
  version (Windows) {
    import core.sys.windows.winbase;
    return GetCurrentThreadId();
  }
  version (Posix) {
    import core.sys.posix.pthread : pthread_self;
    return pthread_self();
  }
}

private __gshared UncheckedMutex outMutex;

/// Logging time info with usecs.
struct LogTime {
  /// Time info except usecs.
  tm t;
  /// Micro seconds.
  long usec;

  alias t this;
}

private LogTime currentTime() {
  // TODO(klknn): Make this @nogc and nothrow.
  const SysTime st = Clock.currTime;
  return LogTime(
      st.toTM(),
      st.fracSecs().total!"usecs" % 1_000_000);
}

private nothrow @nogc
void logImpl(char severity, int line, string f, Args ...)(const(char)* fmt, Args args) {
  LogTime t = assumeNothrowNoGC(&currentTime)();

  // TODO(klknn): Support any buffer outputs in addition to stderr.
  outMutex.lockLazy();
  scope (exit) outMutex.unlock();

  // Based on abseil-py format.
  // https://github.com/abseil/abseil-py/blob/9954557f9df0b346a57ff82688438c55202d2188/absl/logging/__init__.py#L731
  fprintf(
      stderr,
      "%c%02d%02d %02d:%02d:%02d.%06ld %5lu %s:%d] ",
      severity,
      t.tm_mon + 1, t.tm_mday,
      t.tm_hour,
      t.tm_min,
      t.tm_sec,
      t.usec, // TODO(klknn): time.millitm,
      _thisThreadID,
      f.ptr,
      line);
  fprintf(stderr, fmt, args);
  fputc('\n', stderr);
}

/// Emits log at debug level.
/// Params:
///   fmt = C-style format string.
///   args = arguments to be formatted.
///   line = line number where this log is created.
///   file = file name where this log is created.
nothrow @nogc
void logDebug(int line = __LINE__, string file = __FILE__, Args ...)(const(char)* fmt, Args args) {
  debug logImpl!('D', line, file)(fmt, args);
}

/// Emits log at info level.
/// Params:
///   fmt = C-style format string.
///   args = arguments to be formatted.
///   line = line number where this log is created.
///   file = file name where this log is created.
nothrow @nogc
void logInfo(int line = __LINE__, string file = __FILE__, Args ...)(const(char)* fmt, Args args) {
  logImpl!('I', line, file)(fmt, args);
}

/// Emits log at warning level.
/// Params:
///   fmt = C-style format string.
///   args = arguments to be formatted.
///   line = line number where this log is created.
///   file = file name where this log is created.
nothrow @nogc
void logWarn(int line = __LINE__, string file = __FILE__, Args ...)(const(char)* fmt, Args args) {
  logImpl!('W', line, file)(fmt, args);
}

/// Emits log at error level.
/// Params:
///   fmt = C-style format string.
///   args = arguments to be formatted.
///   line = line number where this log is created.
///   file = file name where this log is created.
nothrow @nogc
void logError(int line = __LINE__, string file = __FILE__, Args ...)(const(char)* fmt, Args args) {
  logImpl!('E', line, file)(fmt, args);
  assert(false);
}

unittest {
  import core.thread;
  import core.time;

  auto other = new Thread({
      foreach (i; 0 .. 2) {
        logInfo("%d-th log from other thread %lu.", i, _thisThreadID);
        Thread.sleep(dur!"msecs"(10));
      }
    }).start();
  foreach (i; 0 .. 2) {
    logInfo("%d-th log from this thread %lu.", i, _thisThreadID);
    Thread.sleep(dur!"msecs"(10));
  }
  other.join();
}
