//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui
import "components" as Components
import "." as Plugin
import "tabs" as Tabs

ShellRoot {
  id: harness
  property string outPath: Quickshell.env("QUADRANT_RENDER_OUT")
  property string tab: Quickshell.env("QUADRANT_RENDER_TAB") || "cpu"
  property string palette: Quickshell.env("QUADRANT_RENDER_PALETTE")
  property bool showHeader: Quickshell.env("QUADRANT_RENDER_HEADER") === "1" && tab !== "bar"

  // Palette fixtures affect this throwaway process only; the installed theme
  // and user configuration are never changed.
  function applyPalette() {
    if (palette === "") return
    Commons.Color.shellValues = ({})
    Commons.Color.background = palette === "light" ? "#faf6ef" : palette === "mono" ? "#000000" : "#081217"
    Commons.Color.foreground = palette === "light" ? "#3d3b50" : palette === "mono" ? "#eeeeee" : "#c8d8de"
    Commons.Color.accent = palette === "light" ? "#5850a0" : palette === "mono" ? "#cccccc" : "#70b7be"
    Commons.Color.urgent = palette === "mono" ? "#ffffff" : "#b34b4b"
  }

  Components.Store {
    id: renderStore
    embedded: true
    settingsRaw: ({
      gpuGraphLayout: Quickshell.env("QUADRANT_RENDER_GPU_LAYOUT") || "overlay",
      networkGraphLayout: Quickshell.env("QUADRANT_RENDER_NETWORK_LAYOUT") || "overlay",
      diskGraphLayout: Quickshell.env("QUADRANT_RENDER_DISK_LAYOUT") || "overlay"
    })
  }

  QtObject {
    id: fakeBar
    property string fontFamily: Commons.Style.font.family
    property color barForeground: Commons.Color.foreground
    property color foreground: Commons.Color.foreground
    property color background: Commons.Color.background
    property color urgent: Commons.Color.urgent
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
    property bool settingsOpen: harness.tab === "settings"
    property bool longWindow: Quickshell.env("QUADRANT_RENDER_LONG") === "1"
    property int cursorIndex: -1
    property bool cursorActive: false
    function hoverRow(index, on) { cursorActive = on; cursorIndex = on ? index : -1 }
    property string currentTab: harness.tab
    property color barForeground: Commons.Color.foreground
    property var bar: fakeBar
    property int processCount: renderStore.processCount
    property int panelIntervalMs: renderStore.panelIntervalMs
    readonly property var tabLabels: ({ cpu: "CPU", gpu: "GPU", mem: "Memory", disk: "Drives", net: "Network" })
    readonly property var tabKeys: renderStore.discreteGpuAvailable || harness.tab === "gpu" ? ["cpu", "gpu", "mem", "disk", "net"] : ["cpu", "mem", "disk", "net"]
  }

  Window {
    id: win
    width: Number(Quickshell.env("QUADRANT_RENDER_WIDTH")) || 440
    height: Number(Quickshell.env("QUADRANT_RENDER_HEIGHT")) || (Quickshell.env("QUADRANT_RENDER_FIT") === "1" ? Math.ceil(col.implicitHeight) + 32 : 1100)
    visible: true
    color: Commons.Color.background

    // grabToImage captures contentItem, not the Window's clear colour.
    Rectangle { anchors.fill: parent; color: Commons.Color.background }

    Column {
      id: col
      x: 16; y: 16
      width: parent.width - 32
      spacing: harness.showHeader ? Commons.Style.space(10) : 0
      Components.PanelHeader {
        visible: harness.showHeader
        width: parent.width
        options: fakePanel.tabKeys.map(function (t) { return { value: t, label: fakePanel.tabLabels[t] } })
        currentTab: harness.tab
        settingsOpen: fakePanel.settingsOpen
        resourceName: fakePanel.tabLabels[harness.tab] || "CPU"
        barToggleVisible: !fakePanel.settingsOpen
        barEnabled: renderStore.segmentEnabled(harness.tab === "mem" ? "memory" : harness.tab === "disk" ? "disk" : harness.tab === "net" ? "network" : harness.tab)
      }
      Ui.PanelSeparator { visible: harness.showHeader; width: parent.width }
      Loader {
        onLoaded: {
          if (item && item.processList && Quickshell.env("QUADRANT_RENDER_EXPANDED") === "1") {
            item.processList.expanded = true
            item.processList.query = Quickshell.env("QUADRANT_RENDER_QUERY")
          }
        }
        width: parent.width
        sourceComponent: harness.tab === "cpu" ? cpuC : harness.tab === "mem" ? memC : harness.tab === "gpu" ? gpuC : harness.tab === "disk" ? diskC : harness.tab === "settings" ? settingsC : harness.tab === "bar" ? barC : netC
      }
    }
  }
  Component { id: cpuC; Tabs.CpuTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: memC; Tabs.MemoryTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: gpuC; Tabs.GpuTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: diskC; Tabs.DiskTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: netC; Tabs.NetworkTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: settingsC; Components.SettingsView { width: col.width; store: renderStore } }
  // The bar slot itself, on a strip the height of the bar, driven by the
  // real BarWidget root (its Panel loader fails offscreen; that is fine).
  Component {
    id: barC
    Rectangle {
      width: col.width
      height: fakeBar.vertical ? Math.max(26, slot.implicitHeight) : 26
      color: Commons.Color.bar.background
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

  Component.onCompleted: renderStore.setViewer("render", { gpuSegment: true, gpuTab: true, cpuTab: true, memTab: true, diskTab: true, netTab: true, expandedProcesses: Quickshell.env("QUADRANT_RENDER_EXPANDED") === "1", open: true })

  Timer {
    interval: 7000
    running: true
    onTriggered: {
      harness.applyPalette()
      win.color = Commons.Color.background
      win.contentItem.grabToImage(function (r) {
        r.saveToFile(harness.outPath)
        console.log("RENDER saved " + harness.outPath)
        Qt.quit()
      })
    }
  }
}
