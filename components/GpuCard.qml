import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model
import "." as Components

// Compact graphics block for the CPU tab's integrated GPU: a busy ring
// beside the card's identity, then a few stat rows. Live metrics come
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
    spacing: Commons.Style.space(8)

    Components.SectionHeader {
      width: parent.width
      text: "GRAPHICS"
      note: root.busyIsEstimate && root.busyPct >= 0 ? "frequency estimate" : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      textFormat: Text.PlainText
      visible: root.errorText !== ""
      text: root.errorText
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Commons.Style.space(14)

      Components.RingGauge {
        size: Commons.Style.space(72)
        thickness: Commons.Style.space(7)
        fraction: root.busyPct < 0 ? 0 : root.busyPct / 100
        color: root.pal.primary
        centerText: root.busyPct < 0 ? "--" : Model.formatPct(root.busyPct)
        subText: root.busyIsEstimate ? "freq" : "busy"
        foreground: root.foreground
        fontFamily: root.fontFamily
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: Math.max(0, parent.width - Commons.Style.space(72) - parent.spacing)
        spacing: Commons.Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: root.gpuTitle
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.subtitle
          font.bold: true
          width: parent.width
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          text: root.gpuMeta
          color: root.pal.dim
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.caption
          width: parent.width
          elide: Text.ElideRight
        }
        Components.StatRow {
          width: parent.width
          label: root.intel ? "Frequency" : "Core clock"
          value: root.freqText
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        Components.StatRow {
          width: parent.width
          visible: root.live && root.live.tempC !== null && root.live.tempC !== undefined
          label: "Temperature"
          value: root.live ? Model.formatTemp(root.live.tempC, root.temperatureUnit) : "--"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        Components.StatRow {
          width: parent.width
          visible: root.vramText !== "--"
          label: root.live && root.live.memKind === "shared" ? "Shared" : "VRAM"
          value: root.vramText
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
      }
    }
    Components.StatRow {
      width: parent.width
      visible: root.live && root.live.memoryClockSource !== undefined && root.live.memoryClockSource !== ""
      label: "Memory clock"
      value: Model.formatGpuClock(root.live ? root.live.memoryClockMhz : null)
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}
