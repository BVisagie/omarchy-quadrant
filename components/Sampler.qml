import QtQuick
import Quickshell.Io

// One-shot helper runner: Process + StdioCollector + kill watchdog in one
// place. `result(text)` carries the helper's stdout once the stream closes;
// `failed(message)` fires on a non-zero exit (after the text, if any) or a
// timeout. The watchdog sends SIGTERM first so a helper can clean up, then
// SIGKILL one second later if it is wedged.
Item {
  id: root

  property var command: []
  property int timeoutMs: 6000
  readonly property bool running: proc.running

  signal result(string text)
  signal failed(string message)

  function run() {
    if (proc.running) return false
    killTimer.stop()
    watchdog.restart()
    proc.running = true
    return true
  }

  function stop() {
    watchdog.stop()
    killTimer.stop()
    if (proc.running) proc.signal(15)
  }

  Process {
    id: proc
    command: root.command
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.result(text)
    }
    onExited: function (exitCode) {
      watchdog.stop()
      killTimer.stop()
      if (exitCode !== 0) root.failed("exited with code " + exitCode)
    }
  }

  Timer {
    id: watchdog
    interval: root.timeoutMs
    repeat: false
    onTriggered: {
      if (!proc.running) return
      proc.signal(15)
      killTimer.restart()
      root.failed("timed out")
    }
  }

  Timer {
    id: killTimer
    interval: 1000
    repeat: false
    onTriggered: if (proc.running) proc.signal(9)
  }
}
