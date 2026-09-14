import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "../components" as Components

// GPU tab. AMD and Intel data ride the 1 Hz stream (sysfs); NVIDIA data
// comes from the widget's on-demand nvidia-smi sampler. Per-process GPU
// attribution is deliberately out of scope for v1 (fdinfo/compute-apps
// parsing lands behind a fixture-tested parser later).
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "gpu"
  readonly property var gpu: model ? model.gpu : null
  readonly property string vendor: gpu ? gpu.vendor : ""
  // Unified live view: nvidia rows arrive via model.nvidiaGpu; amd/intel
  // sysfs via the stream, with DRM fdinfo overlaid when sampled.
  readonly property var live: {
    if (!model) return null
    if (vendor === "nvidia") return model.nvidiaGpu
    if (model.discreteGpuLive) return model.discreteGpuLive
    return model.sample ? model.sample.gpu : null
  }
  readonly property string nvidiaError: model ? model.nvidiaError : ""
  readonly property var gpuInfo: {
    if (!model || !model.sysInfo || !model.sysInfo.gpusByCard || !gpu) return null
    return model.sysInfo.gpusByCard[gpu.card] || null
  }

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    // Stream-fed vendors need no panel sampler; NVIDIA and DRM polls
    // run from the widget while this tab is open — nudge them.
    if (model && model.refreshSysInfo) model.refreshSysInfo()
    if (model && vendor === "nvidia" && model.pollNvidia) model.pollNvidia()
    if (model && model.pollDiscreteGpu) model.pollDiscreteGpu()
  }

  readonly property string gpuTitle: {
    if (vendor === "nvidia" && live && live.name) return Model.cleanGpuName(live.name)
    if (gpuInfo && gpuInfo.name) return Model.cleanGpuName(gpuInfo.name)
    if (gpuInfo && gpuInfo.pciId) return Model.gpuVendorLabel(vendor) + " · " + gpuInfo.pciId
    if (vendor) return Model.gpuVendorLabel(vendor)
    return "GPU"
  }

  readonly property string gpuMeta: {
    var parts = []
    if (vendor) parts.push(Model.gpuVendorLabel(vendor))
    if (gpu && gpu.card) parts.push(gpu.card)
    if (gpuInfo && gpuInfo.driver) parts.push("driver " + gpuInfo.driver)
    if (gpuInfo && gpuInfo.slot) parts.push(gpuInfo.slot)
    return parts.join(" · ")
  }

  readonly property string gpuDetail: {
    if (!live) return ""
    if (vendor === "nvidia") {
      var nvidiaTotal = Model.nvidiaMiBToBytes(live.memTotalM)
      if (nvidiaTotal === null) return ""
      return Model.formatBytes(nvidiaTotal) + " VRAM"
    }
    if (live.vramTotal === null || live.vramTotal === undefined) return ""
    return Model.formatBytes(live.vramTotal) + " VRAM"
  }

  function busyText() {
    if (!live) return "--"
    if (vendor === "nvidia")
      return live.utilPct === null ? "--" : Model.formatPct(live.utilPct, 1)
    if (live.busy !== null && live.busy !== undefined)
      return Model.formatPct(live.busy, 1)
    if (vendor === "intel" && live.freqCurMhz !== null && live.freqMaxMhz !== null && live.freqMaxMhz > 0)
      return Model.formatPct(Model.clamp(100 * live.freqCurMhz / live.freqMaxMhz, 0, 100), 1)
    return "--"
  }

  readonly property bool busyIsEstimate: {
    if (!live || vendor === "nvidia") return false
    if (live.busy !== null && live.busy !== undefined) return live.busySource !== "drm" && live.busySource !== "sysfs"
    return vendor === "intel"
  }

  function vramFraction() {
    if (!live) return 0
    var used = vendor === "nvidia" ? live.memUsedM : live.vramUsed
    var total = vendor === "nvidia" ? live.memTotalM : live.vramTotal
    if (used === null || total === null || total <= 0) return 0
    return Model.clamp(used / total, 0, 1)
  }

  function vramText() {
    if (!live) return "--"
    if (vendor === "nvidia") {
      var used = Model.nvidiaMiBToBytes(live.memUsedM)
      var total = Model.nvidiaMiBToBytes(live.memTotalM)
      if (used === null || total === null) return "--"
      return Model.formatBytes(used) + " of " + Model.formatBytes(total)
    }
    if (live.vramUsed === null || live.vramUsed === undefined) return "--"
    if (live.vramTotal === null || live.vramTotal === undefined)
      return Model.formatBytes(live.vramUsed)
    return Model.formatBytes(live.vramUsed) + " of " + Model.formatBytes(live.vramTotal)
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    Components.HardwareHero {
      width: parent.width
      visible: root.vendor !== ""
      title: root.gpuTitle
      meta: root.gpuMeta
      detail: root.gpuDetail
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    // Multi-GPU selector — only when more than one card was detected.
    Row {
      visible: root.model && root.model.discreteGpus && root.model.discreteGpus.length > 1
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: "Card"
        color: root.panel ? Qt.darker(root.panel.barForeground, 1.4) : "#cacccc"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Repeater {
        model: root.model && root.model.discreteGpus ? root.model.discreteGpus : []

        delegate: Rectangle {
          required property var modelData
          readonly property bool current: root.gpu && root.gpu.card === modelData.card
          width: cardLabel.implicitWidth + Style.space(12)
          height: cardLabel.implicitHeight + Style.space(6)
          radius: Style.cornerRadius
          color: current ? Style.selectedFillFor(root.panel ? root.panel.barForeground : "#cacccc", Color.accent)
                         : Style.normalFillFor(root.panel ? root.panel.barForeground : "#cacccc", Color.accent)

          Text {
            id: cardLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.card + " · " + modelData.vendor
            color: root.panel ? root.panel.barForeground : "#cacccc"
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.model) root.model.selectGpu(modelData.card)
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.nvidiaError !== ""
      text: root.nvidiaError
      color: Color.urgent
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(18)
      visible: root.live !== null

      Components.RingGauge {
        size: Style.space(Theme.metrics.largeRingSize)
        thickness: Style.space(Theme.metrics.largeRingThickness)
        fraction: {
          if (!root.live) return 0
          if (root.vendor === "nvidia")
            return root.live.utilPct === null ? 0 : Model.clamp(root.live.utilPct / 100, 0, 1)
          if (root.live.busy !== null && root.live.busy !== undefined)
            return Model.clamp(root.live.busy / 100, 0, 1)
          if (root.vendor === "intel" && root.live.freqCurMhz !== null && root.live.freqMaxMhz > 0)
            return Model.clamp(root.live.freqCurMhz / root.live.freqMaxMhz, 0, 1)
          return 0
        }
        color: Theme.series.gpu
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: root.busyText()
        subText: root.busyIsEstimate ? "freq" : "busy"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }

      Components.RingGauge {
        visible: root.vramText() !== "--"
        size: Style.space(Theme.metrics.largeRingSize)
        thickness: Style.space(Theme.metrics.largeRingThickness)
        fraction: root.vramFraction()
        color: Theme.series.memCache
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: root.live && vramTotalKnown() ? Model.formatPct(root.vramFraction() * 100) : "--"
        subText: root.live && root.live.memKind === "shared" ? "shared" : "VRAM"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Components.StatRow {
      width: parent.width
      label: root.live && root.live.memKind === "shared" ? "Shared" : "VRAM"
      visible: root.vramText() !== "--"
      value: root.vramText()
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Temperature"
      value: root.live ? Model.formatTemp(root.live.tempC) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Power"
      visible: root.vendor !== "intel"
      value: root.live && root.live.powerW !== null ? Model.formatWatts(root.live.powerW) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: root.vendor === "intel" ? "Frequency" : "Core clock"
      value: {
        if (!root.live) return "--"
        if (root.vendor === "intel")
          return Model.formatMhz(root.live.freqCurMhz) + " / " + Model.formatMhz(root.live.freqMaxMhz)
        return Model.formatGpuClock(root.live.clockMhz)
      }
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      visible: root.vendor === "amd" && root.live && root.live.memBusy !== null && root.live.memBusy !== undefined
      label: "Memory busy"
      value: root.live ? Model.formatPct(root.live.memBusy, 1) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Repeater {
      model: root.live && root.live.engines ? root.live.engines : []

      delegate: Components.StatRow {
        required property var modelData
        width: column.width
        label: String(modelData.id || "")
        value: Model.formatPct(modelData.busy, 1)
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.vendor === "intel" && root.busyIsEstimate
      text: "Intel busy % is a frequency ratio until DRM fdinfo returns a sample."
      color: root.panel ? Qt.darker(root.panel.barForeground, 1.5) : "#cacccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }

  function vramTotalKnown() {
    if (!live) return false
    var total = vendor === "nvidia" ? live.memTotalM : live.vramTotal
    return total !== null && total > 0
  }
}
