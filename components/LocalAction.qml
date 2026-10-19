import QtQuick
import Quickshell.Io
import "../lib/index.mjs" as Model

// One explicit user request per runner. A separate job captures its request
// so late output after a device change cannot update the new context.
Item {
  id: root
  visible: false
  property var helperCommand: ["python3", decodeURIComponent(String(Qt.resolvedUrl("../scripts/panel-action.py")).replace(/^file:\/\//, ""))]
  property int timeoutMs: 8000
  property bool busy: false
  property string message: ""
  property bool error: false
  property int serial: 0
  property var activeJob: null
  signal completed(var response)

  function clear() {
    serial++
    // An accepted clipboard/desktop request may already be in the tool.
    // Let it finish before accepting another one; only its old-context
    // feedback is discarded. Killing its wrapper cannot undo the action.
    message = busy ? "Finishing the previous request…" : ""
    error = false
  }
  function run(kind, value) {
    if (busy) return false
    if ((kind !== "copy" && kind !== "open-mount") || typeof value !== "string" || value === "") return false
    serial++
    busy = true; error = false
    message = kind === "copy" ? "Copying…" : "Opening…"
    activeJob = jobComponent.createObject(root, { token: serial, kind: kind, value: value,
      argv: helperCommand.concat([kind]), timeout: timeoutMs })
    return true
  }
  function finish(token, kind, value, response) {
    activeJob = null
    busy = false
    if (token !== serial) { message = ""; error = false; return }
    error = !response || response.ok !== true || response.value !== value
    message = error ? (kind === "copy" ? "Copy failed for " : "Open failed for ") + value + ": "
                      + (response && response.error ? response.error : "The action helper did not confirm this value")
                    : (kind === "copy" ? "Copied " : "Open request sent for ") + value
    completed(response)
  }

  Component {
    id: jobComponent
    Item {
      id: job
      property int token: 0
      property string kind: ""
      property string value: ""
      property var argv: []
      property int timeout: 8000
      property bool finished: false
      function finish(response) {
        if (finished) return
        finished = true
        watchdog.stop()
        if (process.running) process.signal(9)
        root.finish(token, kind, value, response)
        Qt.callLater(job.destroy)
      }
      Process {
        id: process
        command: job.argv
        stdinEnabled: true
        onStarted: write(JSON.stringify({ value: job.value }) + "\n")
        stdout: StdioCollector {
          id: output
          waitForEnd: true
          onStreamFinished: job.finish(Model.safeJson(text))
        }
        onExited: function (exitCode) {
          if (!job.finished) job.finish(Model.safeJson(output.text) || { ok: false, error: "The action helper exited (" + exitCode + ")" })
        }
      }
      Timer {
        id: watchdog
        interval: job.timeout
        onTriggered: job.finish({ ok: false, error: "The action timed out; check your desktop session" })
      }
      Component.onCompleted: { watchdog.start(); process.running = true }
      Component.onDestruction: if (process.running) process.signal(9)
    }
  }
}
