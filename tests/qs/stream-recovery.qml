import QtQuick
import Quickshell
import "components" as Components

// The runner stalls the first and third sampler launches with SIGSTOP.
// Both must recover, including the launch after an intentional settings restart.
ShellRoot {
  id: harness
  property int phase: 0

  Components.Store { id: store; embedded: true }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if ((harness.phase === 0 || harness.phase === 2)
          && store.streamError === "System sampler stopped producing data; restarting") {
        console.log("QRECOVERY stalled " + harness.phase)
        harness.phase++
      } else if ((harness.phase === 1 || harness.phase === 3)
                 && store.streamLive && store.streamError === ""
                 && Date.now() - store.lastSampleAtMs < 1500) {
        console.log("QRECOVERY recovered " + harness.phase)
        if (harness.phase === 1) {
          harness.phase = 2
          store.applySettings({ barIntervalMs: 500 })
        } else {
          console.log("QRECOVERY ok")
          Qt.quit()
        }
      }
    }
  }

  Timer {
    interval: 30000
    running: true
    onTriggered: {
      console.log("QRECOVERY failed " + JSON.stringify({
        phase: harness.phase, live: store.streamLive, error: store.streamError
      }))
      Qt.quit()
    }
  }
}
