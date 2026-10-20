//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui
import "components" as Components
import "." as Plugin
import "tabs" as Tabs
import "graph-data.mjs" as Fixture

ShellRoot {
  id: harness
  property string outPath: Quickshell.env("QUADRANT_RENDER_OUT")
  property string tab: Quickshell.env("QUADRANT_RENDER_TAB") || "cpu"
  property string gpuFixtureMode: Quickshell.env("QUADRANT_RENDER_GPU_FIXTURE")
  property string palette: Quickshell.env("QUADRANT_RENDER_PALETTE")
  property bool actionFixtureEnabled: Quickshell.env("QUADRANT_RENDER_ACTION_FIXTURE") === "1"
  property bool hardwareFixtureEnabled: Quickshell.env("QUADRANT_RENDER_HARDWARE_FIXTURE") === "1"
  property bool showHeader: Quickshell.env("QUADRANT_RENDER_HEADER") === "1" && tab !== "bar"
  property bool documentation: Quickshell.env("QUADRANT_RENDER_DOCUMENTATION") === "1"
  readonly property var renderOptions: ({
    gpuGraphLayout: Quickshell.env("QUADRANT_RENDER_GPU_LAYOUT") || "overlay",
    networkGraphLayout: Quickshell.env("QUADRANT_RENDER_NETWORK_LAYOUT") || "overlay",
    diskGraphLayout: Quickshell.env("QUADRANT_RENDER_DISK_LAYOUT") || "overlay",
    temperatureUnit: Quickshell.env("QUADRANT_RENDER_TEMPERATURE_UNIT") || "celsius"
  })
  readonly property var renderStore: documentation ? documentationFixture : liveStore.item || documentationFixture
  readonly property var viewerState: ({ gpuSegment: tab === "bar", gpuTab: tab === "gpu", cpuTab: tab === "cpu",
    memTab: tab === "mem", diskTab: tab === "disk", netTab: tab === "net", hardwareTab: tab === "hardware" && !hardwareFixtureEnabled,
    expandedProcesses: Quickshell.env("QUADRANT_RENDER_EXPANDED") === "1", open: true })

  // Palette fixtures affect this throwaway process only; the installed theme
  // and user configuration are never changed.
  function applyPalette() {
    if (palette === "") return
    Commons.Color.shellValues = ({})
    Commons.Color.background = palette === "light" ? "#faf6ef" : palette === "mono" ? "#000000" : "#081217"
    Commons.Color.foreground = palette === "light" ? "#3d3b50" : palette === "mono" ? "#eeeeee" : "#c8d8de"
    Commons.Color.accent = palette === "light" ? "#5850a0" : palette === "mono" ? "#cccccc" : "#70b7be"
    Commons.Color.urgent = palette === "mono" ? "#ffffff" : "#b34b4b"
    if (harness.documentation) {
      // The shell's control tokens are separate from Color.shellValues.
      // Fix them too, so a host theme cannot inject its selected colours.
      Commons.Style.styleOverrides = ({ "selected-color": "accent", "normal-color": "foreground" })
    }
  }

  DocumentationFixture {
    id: documentationFixture
    settingsRaw: harness.renderOptions
    expandedProcesses: harness.viewerState.expandedProcesses
  }
  Loader {
    id: liveStore
    active: !harness.documentation
    sourceComponent: Components.Store { embedded: true; settingsRaw: harness.renderOptions }
    onLoaded: item.setViewer("render", harness.viewerState)
  }

  ActionFixture {
    id: actionFixture
    netHistory: Fixture.history(false, "normal")
    netLong: Fixture.history(true, "normal")
    diskHistory: Fixture.history(false, "normal")
    diskLong: Fixture.history(true, "normal")
  }
  HardwareFixture {
    id: hardwareFixture
    cfg: renderStore.cfg
    includeCores: true
  }

  // Optional telemetry for dedicated-GPU presentation on machines without a
  // card. The bytes-only variant reproduces a card with no VRAM denominator.
  QtObject {
    id: gpuFixture
    readonly property bool hasPercentage: harness.gpuFixtureMode !== "bytes"
    readonly property var cfg: renderStore.cfg
    readonly property int barIntervalMs: 1000
    readonly property var gpu: ({ card: "card1", vendor: hasPercentage ? "amd" : "intel", driver: hasPercentage ? "amdgpu" : "i915",
      name: hasPercentage ? "AMD Radeon RX 7800 XT" : "Intel GPU (fixture)" })
    readonly property var discreteGpus: [gpu]
    readonly property var gpuLive: ({ busy: 38, vramUsed: hasPercentage ? 16 * 1073741824 * 0.66 : 4 * 1073741824,
      vramTotal: hasPercentage ? 16 * 1073741824 : null, tempC: 58, powerW: 87, clockMhz: 2140,
      memoryClockMhz: hasPercentage ? 1000 : null, memoryClockSource: hasPercentage ? "pp_dpm_mclk" : "", freqCurMhz: 1100, freqMaxMhz: 2000 })
    readonly property var gpuDisplay: ({ pct: 38, estimated: false })
    readonly property var gpuRows: [{ pid: 4242, comm: "blender", value: 38, vram: 4 * 1073741824, sortKey: 38 }]
    readonly property string nvidiaError: ""
    readonly property var gpuHistory: history(false)
    readonly property var gpuLong: history(true)
    function history(longer) {
      return Fixture.history(longer, "normal").map(function (point) { return { t: point.t, b: point.b, v: gpuFixture.hasPercentage ? point.v : null } })
    }
    function refreshSysInfo() { }
    function pollNvidia() { }
    function pollDiscreteGpu() { }
  }

  QtObject {
    id: fakeBar
    property string fontFamily: Commons.Style.font.family
    property color barForeground: Commons.Color.foreground
    property color foreground: Commons.Color.foreground
    property color background: Commons.Color.background
    property color urgent: Commons.Color.urgent
    property bool vertical: Quickshell.env("QUADRANT_RENDER_VERTICAL") === "1"
    property bool foregroundAnimationEnabled: false
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
    readonly property var tabLabels: ({ cpu: "CPU", gpu: "GPU", mem: "Memory", disk: "Drives", net: "Network", hardware: "Hardware" })
    readonly property var tabKeys: ["cpu", "gpu", "mem", "disk", "net", "hardware"].filter(function (tab) {
      return (tab !== "gpu" || renderStore.discreteGpuAvailable || harness.tab === "gpu" || harness.hardwareFixtureEnabled)
        && (tab !== "hardware" || renderStore.hardwareAvailable || harness.tab === "hardware")
    })
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
        barToggleVisible: !fakePanel.settingsOpen && harness.tab !== "hardware"
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
        sourceComponent: harness.tab === "cpu" ? cpuC : harness.tab === "mem" ? memC : harness.tab === "gpu" ? gpuC : harness.tab === "disk" ? diskC : harness.tab === "hardware" ? hardwareC : harness.tab === "settings" ? settingsC : harness.tab === "bar" ? barC : netC
      }
    }
  }
  Component { id: cpuC; Tabs.CpuTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: memC; Tabs.MemoryTab { width: col.width; panel: fakePanel; model: renderStore } }
  Component { id: gpuC; Tabs.GpuTab { width: col.width; panel: fakePanel; model: harness.gpuFixtureMode ? gpuFixture : renderStore } }
  Component { id: diskC; Tabs.DiskTab { width: col.width; panel: fakePanel; model: harness.actionFixtureEnabled ? actionFixture : renderStore } }
  Component { id: netC; Tabs.NetworkTab { width: col.width; panel: fakePanel; model: harness.actionFixtureEnabled ? actionFixture : renderStore } }
  Component { id: settingsC; Components.SettingsView { width: col.width; store: harness.hardwareFixtureEnabled ? hardwareFixture : renderStore } }
  Component { id: hardwareC; Tabs.HardwareTab { width: col.width; panel: fakePanel; model: harness.hardwareFixtureEnabled ? hardwareFixture : renderStore } }
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

  Timer {
    interval: harness.documentation ? 500 : 7000
    running: true
    onTriggered: {
      harness.applyPalette()
      win.color = Commons.Color.background
      captureTimer.start()
    }
  }
  Timer {
    id: captureTimer
    interval: 200
    onTriggered: {
      // Theme-driven control fills animate; let the fixed palette settle.
      win.contentItem.grabToImage(function (r) {
        r.saveToFile(harness.outPath)
        console.log("RENDER saved " + harness.outPath)
        Qt.quit()
      })
    }
  }
}
