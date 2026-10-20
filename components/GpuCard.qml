import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model
import "." as Components

// Integrated GPU readings inside the CPU tab's graphics card. Metrics come
// from the store's on-demand gpu-stats poll while the CPU tab is open.
Item {
  id: root

  property var gpu: null
  property var gpuInfo: null
  property var live: null
  property string errorText: ""
  property string temperatureUnit: "celsius"
  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family

  readonly property string vendor: gpu ? gpu.vendor : ""
  readonly property bool intel: vendor === "intel"
  readonly property var pal: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent), String(foreground), String(Commons.Color.background))

  visible: gpu !== null
  implicitWidth: 200
  implicitHeight: visible ? column.implicitHeight : 0

  readonly property string gpuTitle: {
    var name = Model.gpuDisplayName(gpuInfo) || Model.gpuDisplayName(gpu)
    if (name) return name
    if (gpuInfo && gpuInfo.pciId) return Model.gpuVendorLabel(vendor) + " · " + gpuInfo.pciId
    if (vendor) return Model.gpuVendorLabel(vendor)
    return "Graphics"
  }
  readonly property string gpuMeta: {
    var parts = []
    if (vendor) parts.push(Model.gpuVendorLabel(vendor))
    if (gpu && gpu.card) parts.push(gpu.card)
    var driver = gpuInfo && gpuInfo.driver ? gpuInfo.driver : (gpu ? gpu.driver : "")
    if (driver) parts.push(driver)
    return parts.join(" · ")
  }
  readonly property bool busyIsEstimate: {
    if (!live) return intel
    if (live.busy !== null && live.busy !== undefined) return live.busySource !== "drm" && live.busySource !== "sysfs"
    return intel
  }
  readonly property real busyPct: {
    if (!live) return -1
    if (live.busy !== null && live.busy !== undefined) return Model.clamp(live.busy, 0, 100)
    if (intel && live.freqCurMhz !== null && live.freqMaxMhz !== null && live.freqMaxMhz > 0)
      return Model.clamp(100 * live.freqCurMhz / live.freqMaxMhz, 0, 100)
    return -1
  }
  readonly property string freqText: {
    if (!live) return "--"
    if (intel) return Model.formatMhz(live.freqCurMhz) + " / " + Model.formatMhz(live.freqMaxMhz)
    return Model.formatGpuClock(live.clockMhz)
  }
  readonly property string vramText: {
    if (!live || live.vramUsed === null || live.vramUsed === undefined) return "--"
    if (live.vramTotal === null || live.vramTotal === undefined) return Model.formatBytes(live.vramUsed)
    return Model.formatBytes(live.vramUsed) + " of " + Model.formatBytes(live.vramTotal)
  }

  Column {
    id: column
    width: root.width
    spacing: Commons.Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: root.gpuTitle
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      font.bold: true
      width: parent.width
      wrapMode: Text.Wrap
    }
    Text {
      textFormat: Text.PlainText
      visible: root.errorText !== ""
      text: root.errorText
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
    }
    Components.MetricReadout {
      objectName: "cpuGpuOverview"
      width: parent.width
      value: root.busyPct < 0 ? "--" : (root.busyIsEstimate ? "~" : "") + Model.formatPct(root.busyPct)
      hint: root.busyIsEstimate ? "Frequency estimate · not measured busy time" : "Busy"
    }
    Components.StatRow {
      width: parent.width
      wrapValue: true
      label: root.intel ? "Frequency" : "Core clock"
      value: root.freqText
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Components.StatRow {
      width: parent.width
      wrapValue: true
      visible: root.live && root.live.tempC !== null && root.live.tempC !== undefined
      label: "Temperature"
      value: root.live ? Model.formatTemp(root.live.tempC, root.temperatureUnit) : "--"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Components.StatRow {
      width: parent.width
      wrapValue: true
      label: root.live && root.live.memKind === "shared" ? "Shared memory" : "VRAM"
      value: root.vramText
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Components.StatRow {
      width: parent.width
      wrapValue: true
      visible: root.live && root.live.memoryClockSource !== undefined && root.live.memoryClockSource !== ""
      label: "Memory clock"
      value: Model.formatGpuClock(root.live ? root.live.memoryClockMhz : null)
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Components.Disclosure {
      width: parent.width
      title: "Graphics details"
      Text {
        textFormat: Text.PlainText
        text: root.gpuMeta
        color: root.pal.dim
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        width: parent.width
        wrapMode: Text.Wrap
      }
    }
  }
}
