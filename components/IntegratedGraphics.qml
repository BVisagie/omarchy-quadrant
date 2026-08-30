import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "." as Components

// Compact integrated-graphics block for the CPU tab. Not a second GPU tab:
// one smaller ring beside identity, then a few optional stat rows. Live
// metrics come from the widget's on-demand gpu-stats poller.
Item {
  id: root

  property var panel: null
  property var gpu: null
  property var gpuInfo: null
  property var live: null
  property string errorText: ""
  property color foreground: "#cacccc"
  property string fontFamily: Style.font.family

  readonly property string vendor: gpu ? gpu.vendor : ""
  readonly property bool intel: vendor === "intel"
  readonly property bool amd: vendor === "amd"

  visible: gpu !== null
  implicitWidth: 200
  implicitHeight: visible ? column.implicitHeight : 0

  readonly property string gpuTitle: {
    if (gpuInfo && gpuInfo.name) return gpuInfo.name
    if (gpu && gpu.name) return gpu.name
    if (gpuInfo && gpuInfo.pciId) return Model.gpuVendorLabel(vendor) + " · " + gpuInfo.pciId
    if (gpu && gpu.pciId) return Model.gpuVendorLabel(vendor) + " · " + gpu.pciId
    if (vendor) return Model.gpuVendorLabel(vendor)
    return "Graphics"
  }

  readonly property string gpuMeta: {
    var parts = []
    if (vendor) parts.push(Model.gpuVendorLabel(vendor))
    if (gpu && gpu.card) parts.push(gpu.card)
    var driver = gpuInfo && gpuInfo.driver ? gpuInfo.driver : (gpu ? gpu.driver : "")
    if (driver) parts.push("driver " + driver)
    return parts.join(" · ")
  }

  readonly property string gpuDetail: {
    if (!live) return ""
    if (intel) {
      if (live.freqCurMhz !== null && live.freqCurMhz !== undefined)
        return Model.formatMhz(live.freqCurMhz)
      return ""
    }
    if (live.busy !== null && live.busy !== undefined) return Model.formatPct(live.busy, 1)
    return ""
  }

  function ringFraction() {
    if (!live) return 0
    if (intel) {
      if (live.freqCurMhz !== null && live.freqMaxMhz !== null && live.freqMaxMhz > 0)
        return Model.clamp(live.freqCurMhz / live.freqMaxMhz, 0, 1)
      return 0
    }
    if (live.busy === null || live.busy === undefined) return 0
    return Model.clamp(live.busy / 100, 0, 1)
  }

  function ringText() {
    if (!live) return "--"
    if (intel) {
      if (live.freqCurMhz !== null && live.freqMaxMhz !== null && live.freqMaxMhz > 0)
        return Model.formatPct(Model.clamp(100 * live.freqCurMhz / live.freqMaxMhz, 0, 100), 1)
      return "--"
    }
    return live.busy === null ? "--" : Model.formatPct(live.busy, 1)
  }

  function freqText() {
    if (!live) return "--"
    if (intel)
      return Model.formatMhz(live.freqCurMhz) + " / " + Model.formatMhz(live.freqMaxMhz)
    return Model.formatMhz(live.clockMhz)
  }

  function vramText() {
    if (!live || live.vramUsed === null || live.vramTotal === null) return "--"
    return Model.formatBytes(live.vramUsed) + " of " + Model.formatBytes(live.vramTotal)
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    PanelSeparator {
      foreground: root.foreground
    }

    Text {
      textFormat: Text.PlainText
      text: "GRAPHICS"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    Text {
      textFormat: Text.PlainText
      visible: root.errorText !== ""
      text: root.errorText
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(14)

      Components.RingGauge {
        size: Style.space(Theme.metrics.ringSize)
        thickness: Style.space(Theme.metrics.ringThickness)
        fraction: root.ringFraction()
        color: Theme.series.gpu
        trackColor: Theme.trackFor(root.foreground)
        centerText: root.ringText()
        subText: root.intel ? "freq" : "busy"
        foreground: root.foreground
        fontFamily: root.fontFamily
        anchors.verticalCenter: parent.verticalCenter
      }

      Components.HardwareHero {
        width: Math.max(0, parent.width - Style.space(Theme.metrics.ringSize) - parent.spacing)
        title: root.gpuTitle
        meta: root.gpuMeta
        detail: root.gpuDetail
        foreground: root.foreground
        fontFamily: root.fontFamily
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Components.StatRow {
      width: parent.width
      label: root.intel ? "Frequency" : "Core clock"
      value: root.freqText()
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Components.StatRow {
      width: parent.width
      visible: root.live && root.live.tempC !== null && root.live.tempC !== undefined
      label: "Temperature"
      value: root.live ? Model.formatTemp(root.live.tempC) : "--"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Components.StatRow {
      width: parent.width
      visible: root.amd && root.live && root.live.vramTotal !== null && root.live.vramTotal > 0
      label: "VRAM"
      value: root.vramText()
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      textFormat: Text.PlainText
      visible: root.intel
      text: "Intel busy % needs CAP_PERFMON; frequency ratio is shown instead."
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
