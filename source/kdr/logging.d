// -*- mode: d; c-basic-offset: 2 -*-
module kdr.logging;

import core.sync.mutex;
import core.time;
import core.thread.types : ThreadID;
import core.stdc.stdio : fprintf, fputc, stderr;
import core.stdc.time : tm;
import std.datetime.systime : Clock, SysTime;

import dplug.core.sync;

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

nothrow @nogc
void logInfo(int line = __LINE__, string f = __FILE__, Args ...)(const(char)* fmt, Args args) {
  tm t;
  long usec;
  debug {
    // TODO(klknn): Make this @nogc.
    SysTime st = Clock.currTime;
    t = st.toTM();
    usec = st.fracSecs().total!"usecs" % 1_000_000;
  }

  // TODO(klknn): Support any buffer outputs in addition to stderr.
  outMutex.lockLazy();
  scope (exit) outMutex.unlock();

  // Based on abseil-py format.
  // https://github.com/abseil/abseil-py/blob/9954557f9df0b346a57ff82688438c55202d2188/absl/logging/__init__.py#L731
  fprintf(
      stderr,
      "%c%02d%02d %02d:%02d:%02d.%06ld %5lu %s:%d] ",
      'I',
      t.tm_mon + 1, t.tm_mday,
      t.tm_hour,
      t.tm_min,
      t.tm_sec,
      usec, // TODO(klknn): time.millitm,
      _thisThreadID,
      f.ptr,
      line);
  fprintf(stderr, fmt, args);
  fputc('\n', stderr);
}

unittest {
  import core.thread;
  import core.time;

  auto other = new Thread({
      foreach (i; 0 .. 3) {
        logInfo("%d-th log from other thread %lu.", i, _thisThreadID);
        Thread.sleep(dur!"msecs"(100));
      }
    }).start();
  foreach (i; 0 .. 3) {
    logInfo("%d-th log from this thread %lu.", i, _thisThreadID);
    Thread.sleep(dur!"msecs"(100));
  }
  other.join();
}
