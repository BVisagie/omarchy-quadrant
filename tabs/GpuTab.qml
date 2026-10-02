import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "../components" as Components

// GPU tab (dedicated cards only): identity, card picker, busy and VRAM
// rings, busy/VRAM history, stat rows and the per-process roster. AMD and
// Intel data ride the stream plus DRM fdinfo; NVIDIA comes from the
// store's on-demand nvidia-smi poll.
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "gpu"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var gpu: model ? model.gpu : null
  readonly property string vendor: gpu ? gpu.vendor : ""
  readonly property var live: model ? model.gpuLive : null
  readonly property var display: model ? model.gpuDisplay : null
  readonly property string nvidiaError: model ? model.nvidiaError : ""
  readonly property var gpuInfo: {
    if (!model || !model.sysInfo || !model.sysInfo.gpusByCard || !gpu) return null
    return model.sysInfo.gpusByCard[gpu.card] || null
  }
  readonly property var pal: Model.seriesPalette(String(Color.accent), String(Color.urgent), String(Color.foreground), String(Color.background))

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (!model) return
    model.refreshSysInfo()
    if (vendor === "nvidia") model.pollNvidia()
    model.pollDiscreteGpu()
  }

  // ---- identity ----------------------------------------------------------
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
    if (gpuInfo && gpuInfo.driver) parts.push(gpuInfo.driver)
    return parts.join(" · ")
  }
  readonly property string gpuDetail: {
    if (!live) return ""
    if (vendor === "nvidia") {
      var t = Model.nvidiaMiBToBytes(live.memTotalM)
      return t === null ? "" : Model.formatBytes(t) + " VRAM"
    }
    if (live.vramTotal === null || live.vramTotal === undefined) return ""
    return Model.formatBytes(live.vramTotal) + " VRAM"
  }
  readonly property var cardOptions: {
    var list = model && model.discreteGpus ? model.discreteGpus : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var g = list[i]
      var info = model && model.sysInfo && model.sysInfo.gpusByCard ? model.sysInfo.gpusByCard[g.card] : null
      var name = info && info.name ? Model.cleanGpuName(info.name) : Model.gpuVendorLabel(g.vendor)
      out.push({ value: g.card, label: name, tooltip: g.card + " · " + g.vendor })
    }
    return out
  }

  // ---- live --------------------------------------------------------------
  readonly property real vramPct: {
    var p = Model.gpuVramPct(live)
    return p === null ? -1 : p
  }
  readonly property string vramText: {
    if (!live) return "--"
    if (vendor === "nvidia") {
      var used = Model.nvidiaMiBToBytes(live.memUsedM)
      var total = Model.nvidiaMiBToBytes(live.memTotalM)
      if (used === null || total === null) return "--"
      return Model.formatBytes(used) + " of " + Model.formatBytes(total)
    }
    if (live.vramUsed === null || live.vramUsed === undefined) return "--"
    if (live.vramTotal === null || live.vramTotal === undefined) return Model.formatBytes(live.vramUsed)
    return Model.formatBytes(live.vramUsed) + " of " + Model.formatBytes(live.vramTotal)
  }
  readonly property string tempText: {
    if (!live || live.tempC === null || live.tempC === undefined) return "--"
    var t = Model.formatTemp(live.tempC)
    if (live.tempJunctionC !== null && live.tempJunctionC !== undefined) t += " · " + Model.formatTemp(live.tempJunctionC) + " junction"
    return t
  }
  readonly property string clockText: {
    if (!live) return "--"
    if (vendor === "intel") return Model.formatMhz(live.freqCurMhz) + " / " + Model.formatMhz(live.freqMaxMhz)
    return Model.formatGpuClock(live.clockMhz)
  }

  // ---- rows --------------------------------------------------------------
  readonly property var rows: {
    var src = model ? model.gpuRows : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      var r = src[i]
      var text = root.vendor === "nvidia" ? Model.formatBytes(r.vram) : Model.formatPct(r.value, 1)
      out.push({ pid: r.pid, comm: r.comm, valueText: text, sortKey: r.sortKey,
                 hint: r.vram > 0 ? Model.formatBytes(r.vram) + " resident" : "" })
    }
    return out
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(10)

    Components.Hero {
      width: parent.width
      visible: root.vendor !== ""
      title: root.gpuTitle
      meta: root.gpuMeta
      detail: root.gpuDetail
    }

    ButtonGroup {
      visible: root.cardOptions.length > 1
      options: root.cardOptions
      value: root.gpu ? root.gpu.card : ""
      fontSize: Style.font.caption
      onChanged: function (value) { if (root.model) root.model.selectGpu(value) }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.nvidiaError !== ""
      text: root.nvidiaError
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(18)

      Components.RingGauge {
        size: Style.space(96)
        fraction: root.display ? root.display.pct / 100 : 0
        color: root.pal.primary
        centerText: root.display ? (root.display.estimated ? "~" : "") + Model.formatPct(root.display.pct, 1) : "--"
        subText: root.display && root.display.estimated ? "freq" : "busy"
        anchors.verticalCenter: parent.verticalCenter
      }

      Components.RingGauge {
        visible: root.vramPct >= 0
        size: Style.space(96)
        fraction: root.vramPct < 0 ? 0 : root.vramPct / 100
        color: root.pal.secondary
        centerText: root.vramPct < 0 ? "--" : Model.formatPct(root.vramPct)
        subText: root.live && root.live.memKind === "shared" ? "shared" : "VRAM"
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Components.GraphBlock {
      width: parent.width
      title: "HISTORY"
      finePoints: root.model ? root.model.gpuHistory : []
      longPoints: root.model ? root.model.gpuLong : []
      longWindow: root.longWindow
      fixedMax: 100
      fields: [
        { key: "b", label: "busy", color: root.pal.primary },
        { key: "v", label: "VRAM", color: root.pal.secondary }
      ]
      legend: [
        { label: "busy", color: root.pal.primary, value: root.display ? Model.formatPct(root.display.pct) : "--" },
        { label: "VRAM", color: root.pal.secondary, value: root.vramPct < 0 ? "--" : Model.formatPct(root.vramPct), visible: root.vramPct >= 0 }
      ]
      onToggleWindow: if (root.panel) root.panel.longWindow = !root.panel.longWindow
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Components.StatRow {
        width: parent.width
        visible: root.vramText !== "--"
        label: root.live && root.live.memKind === "shared" ? "Shared" : "VRAM"
        value: root.vramText
      }
      Components.StatRow {
        width: parent.width
        label: "Temperature"
        value: root.tempText
      }
      Components.StatRow {
        width: parent.width
        visible: root.vendor !== "intel"
        label: "Power"
        value: root.live && root.live.powerW !== null && root.live.powerW !== undefined ? Model.formatWatts(root.live.powerW) : "--"
      }
      Components.StatRow {
        width: parent.width
        label: root.vendor === "intel" ? "Frequency" : "Core clock"
        value: root.clockText
      }
      Components.StatRow {
        width: parent.width
        visible: root.vendor === "amd" && root.live && root.live.memBusy !== null && root.live.memBusy !== undefined
        label: "Memory busy"
        value: root.live ? Model.formatPct(root.live.memBusy, 1) : "--"
      }
      Repeater {
        model: root.live && root.live.engines ? root.live.engines : []
        delegate: Components.StatRow {
          required property var modelData
          width: column.width
          label: String(modelData.id || "")
          value: Model.formatPct(modelData.busy, 1)
        }
      }
    }

    PanelSeparator { }

    Components.ProcessList {
      width: parent.width
      rows: root.rows
      cursorIndex: root.panel ? root.panel.cursorIndex : -1
      cursorActive: root.panel ? root.panel.cursorActive === true : false
      onRowHovered: function (index, on) { if (root.panel && root.panel.hoverRow) root.panel.hoverRow(index, on) }
      valueHeader: root.vendor === "nvidia" ? "VRAM" : "GPU"
      showSparkline: false
      emptyText: root.active ? "No process is using the GPU" : "Open this tab to sample processes"
      errorText: ""
    }

    Text {
      textFormat: Text.PlainText
      visible: root.vendor === "nvidia" && root.rows.length > 0
      text: "NVIDIA reports per-process memory only; busy time is per card."
      color: root.pal.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
