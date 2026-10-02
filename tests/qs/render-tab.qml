import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "components" as Components
import "." as Plugin
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
    property color background: Color.background
    property color urgent: Color.urgent
    property bool vertical: Quickshell.env("QUADRANT_RENDER_VERTICAL") === "1"
    property int barSize: 26
    property string position: "top"
    property var shell: null
    property var clickTargets: []
    function showTooltip(target, text) { console.log("TOOLTIP " + text) }
    function hideTooltip(target) { }
    function registerClickTarget(t) { var n = clickTargets.slice(); n.push(t); clickTargets = n }
    function unregisterClickTarget(t) { clickTargets = clickTargets.filter(function (x) { return x !== t }) }
    function switchPanelFrom(owner, dir) { return false }
    function moduleWidgets(id) { return [] }
    function run(cmd) { console.log("RUN " + cmd) }
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
        sourceComponent: harness.tab === "cpu" ? cpuC : harness.tab === "mem" ? memC : harness.tab === "gpu" ? gpuC : harness.tab === "disk" ? diskC : harness.tab === "settings" ? settingsC : harness.tab === "bar" ? barC : netC
      }
    }
  }
  Component { id: cpuC; Tabs.CpuTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: memC; Tabs.MemoryTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: gpuC; Tabs.GpuTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: diskC; Tabs.DiskTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: netC; Tabs.NetworkTab { width: col.width; panel: fakePanel; model: store } }
  Component { id: settingsC; Components.SettingsView { width: col.width; store: store } }
  // The bar slot itself, on a strip the height of the bar, driven by the
  // real BarWidget root (its Panel loader fails offscreen; that is fine).
  Component {
    id: barC
    Rectangle {
      width: col.width
      height: 26
      color: Color.bar.background
      Plugin.BarWidget {
        id: slot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        height: implicitHeight
        bar: fakeBar
        settings: ({})
        Component.onCompleted: console.log("BAR implicitWidth=" + implicitWidth + " cells=" + JSON.stringify(slot.store ? slot.store.visibleBarCells : null))
      }
      Timer { interval: 5000; running: true; onTriggered: console.log("BAR later implicitWidth=" + slot.implicitWidth + " cells=" + JSON.stringify(slot.store ? slot.store.visibleBarCells : null)) }
    }
  }

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
