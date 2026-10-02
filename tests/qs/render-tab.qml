import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "components" as Components
import "tabs" as Tabs

ShellRoot {
  id: harness
  property string outPath: Quickshell.env("QUADRANT_RENDER_OUT")
  property string tab: Quickshell.env("QUADRANT_RENDER_TAB") || "cpu"

  Components.Store { id: store; embedded: true }

  QtObject {
    id: fakeBar
    property string fontFamily: Style.font.family
    property color barForeground: Color.foreground
    property color foreground: Color.foreground
    property color urgent: Color.urgent
    property bool vertical: false
    property int barSize: 26
  }
  QtObject {
    id: fakePanel
    property bool opened: true
    property bool longWindow: Quickshell.env("QUADRANT_RENDER_LONG") === "1"
    property int cursorIndex: -1
    property bool cursorActive: false
    function hoverRow(index, on) { cursorActive = on; cursorIndex = on ? index : -1 }
    property string currentTab: harness.tab
    property color barForeground: Color.foreground
    property var bar: fakeBar
    property int processCount: store.processCount
    property int panelIntervalMs: store.panelIntervalMs
  }

  Window {
    id: win
    width: 440
    height: 1100
    visible: true
    color: Color.background

    Column {
      id: col
      x: 16; y: 16
      width: parent.width - 32
      spacing: 0
      Loader {
        width: parent.width
        sourceComponent: harness.tab === "cpu" ? cpuC : harness.tab === "mem" ? memC : harness.tab === "gpu" ? gpuC : harness.tab === "disk" ? diskC : harness.tab === "settings" ? settingsC : netC
      }
    }
  }
  Component { id: cpuC; Tabs.CpuTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: memC; Tabs.MemoryTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: gpuC; Tabs.GpuTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: diskC; Tabs.DiskTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: netC; Tabs.NetworkTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: settingsC; Components.SettingsView { width: col.width; store: store } }

  Component.onCompleted: store.setViewer("render", { gpuSegment: true, gpuTab: true, cpuTab: true, memTab: true, diskTab: true, netTab: true, open: true })

  Timer {
    interval: 7000
    running: true
    onTriggered: {
      win.color = Color.background
      win.contentItem.grabToImage(function (r) {
        r.saveToFile(harness.outPath)
        console.log("RENDER saved " + harness.outPath)
        Qt.quit()
      })
    }
  }
}
