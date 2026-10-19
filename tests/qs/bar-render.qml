//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons as Commons
import "." as Plugin
import "components" as Components
import "lib/index.mjs" as Model

ShellRoot {
  id: harness
  property string outPath: Quickshell.env("QUADRANT_RENDER_OUT")
  property string palette: Quickshell.env("QUADRANT_RENDER_PALETTE") || "dark"
  property string style: Quickshell.env("QUADRANT_RENDER_BAR_STYLE") || "graph-text"
  property bool vertical: Quickshell.env("QUADRANT_RENDER_VERTICAL") === "1"
  property bool showSettings: Quickshell.env("QUADRANT_RENDER_TAB") === "settings"
  property bool missingGpu: Quickshell.env("QUADRANT_RENDER_MISSING_GPU") === "1"
  property string gpuVendor: Model.parseEnumSetting(Quickshell.env("QUADRANT_RENDER_GPU_VENDOR"), ["intel", "amd", "nvidia"], "intel")
  property real stripSize: Number(Quickshell.env("QUADRANT_RENDER_BAR_SIZE")) || 26
  property var order: Model.barOrderFromSetting(Quickshell.env("QUADRANT_RENDER_ORDER") || "network,cpu,gpu,memory,disk")
  property int graphWidth: Number(Quickshell.env("QUADRANT_RENDER_GRAPH_WIDTH")) || 32
  property string labels: Quickshell.env("QUADRANT_RENDER_LABELS") || "glyph"
  property int duration: Number(Quickshell.env("QUADRANT_BENCH_SECONDS")) || 0
  property real timestamp: 1000
  property int copies: Math.max(1, Math.min(2, Number(Quickshell.env("QUADRANT_RENDER_MONITORS")) || 1))
  BarFixture {
    id: shared
    discreteGpuAvailable: !harness.missingGpu
    gpu: ({ vendor: harness.gpuVendor })
    settingsRaw: ({ barStyle: harness.style, barOrder: harness.order, barGraphWidth: harness.graphWidth,
      barLabels: harness.labels, segments: ["cpu", "gpu", "memory", "disk", "network"] })
  }
  BarHost { id: host; service: shared; vertical: harness.vertical; barSize: harness.stripSize; widgets: secondSlot.item ? [slot, secondSlot.item] : [slot] }
  function applyPalette() {
    if (!duration) Commons.Color.shellValues = ({})
    Commons.Color.background = palette === "light" ? "#faf6ef" : palette === "mono" ? "#000000" : "#081217"
    Commons.Color.foreground = palette === "light" ? "#3d3b50" : palette === "mono" ? "#eeeeee" : "#c8d8de"
    Commons.Color.accent = palette === "light" ? "#5850a0" : palette === "mono" ? "#cccccc" : "#70b7be"
    Commons.Color.urgent = palette === "mono" ? "#ffffff" : "#b34b4b"
  }
  Window {
    id: win
    visible: true
    width: harness.showSettings ? 440 : Math.max(400, slot.implicitWidth + 32)
    height: harness.showSettings ? settings.implicitHeight + 32 : harness.vertical ? slot.implicitHeight + 80 : harness.copies * (slot.implicitHeight + 12) + 68
    color: Commons.Color.background
    Rectangle { anchors.fill: parent; color: Commons.Color.background }
    Text {
      visible: !harness.showSettings
      x: 16; y: 10; width: parent.width - 32
      textFormat: Text.PlainText
      text: (harness.vertical ? "Vertical" : "Horizontal") + " · " + harness.style + " · " + harness.palette + "\nSynthetic history · one minute · " + (harness.missingGpu ? "GPU absent" : "all devices")
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      color: Commons.Color.foreground
    }
    Plugin.BarWidget {
      id: slot
      visible: !harness.showSettings
      x: 16; y: 64
      width: implicitWidth
      height: implicitHeight
      bar: host
      settings: shared.settingsRaw
    }
    Loader {
      id: secondSlot
      active: harness.copies > 1 && !harness.showSettings
      x: harness.vertical ? slot.x + slot.width + 24 : slot.x
      y: harness.vertical ? slot.y : slot.y + slot.height + 12
      width: item ? item.implicitWidth : 0
      height: item ? item.implicitHeight : 0
      sourceComponent: Plugin.BarWidget { width: implicitWidth; height: implicitHeight; bar: host; settings: shared.settingsRaw }
    }
    Components.SettingsView { id: settings; x: 16; y: 16; width: 408; visible: harness.showSettings; store: shared }
  }
  Component.onCompleted: shared.seed(timestamp)
  Timer {
    interval: shared.barIntervalMs
    repeat: true
    running: harness.duration > 0
    onTriggered: { harness.timestamp += interval / 1000; shared.pulse(harness.timestamp) }
  }
  Timer {
    interval: 300
    running: true
    onTriggered: { harness.applyPalette(); captureTimer.start() }
  }
  Timer {
    id: captureTimer
    interval: harness.duration > 0 ? harness.duration * 1000 : 300
    onTriggered: {
      var valueFonts = {}
      if (typeof slot.valueFontSizeFor === "function")
        for (var metric of slot.visibleBarCells) valueFonts[metric] = slot.valueFontSizeFor(metric)
      console.log("BAR_LAYOUT " + JSON.stringify({ width: slot.implicitWidth, height: slot.implicitHeight, cells: slot.visibleBarCells,
        viewers: Object.keys(shared.viewers).length, storeTries: slot.storeTries, font: Commons.Style.font.caption,
        gpuVendor: harness.gpuVendor, valueFonts: valueFonts }))
      win.contentItem.grabToImage(function (result) { result.saveToFile(harness.outPath); Qt.quit() })
    }
  }
}
