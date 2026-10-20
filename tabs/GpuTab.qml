import QtQuick
import qs.Commons as Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "../components" as Components

// GPU tab (dedicated cards only): identity, card picker, grouped readings,
// busy/VRAM history, stat rows and the per-process roster. AMD and
// Intel data ride the stream plus DRM fdinfo; NVIDIA comes from the
// store's on-demand nvidia-smi poll.
Item {
  id: root

  property var panel: null
  property var model: null
  property alias processList: processRoster

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "gpu"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var gpu: model ? model.gpu : null
  readonly property string vendor: gpu ? gpu.vendor : ""
  readonly property var live: model ? model.gpuLive : null
  readonly property var display: model ? model.gpuDisplay : null
  readonly property string nvidiaError: model ? model.nvidiaError : ""
  readonly property var gpuInfo: gpu
  readonly property var pal: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent), String(Commons.Color.foreground), String(Commons.Color.background))

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
    var name = Model.gpuDisplayName(gpuInfo)
    if (name) return name
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
  readonly property var cardOptions: {
    var list = model && model.discreteGpus ? model.discreteGpus : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var g = list[i]
      var name = Model.gpuDisplayName(g) || Model.gpuVendorLabel(g.vendor)
      out.push({ value: g.card, label: name, tooltip: (g.deviceId ? g.deviceId + " · " : "") + g.card + " · " + g.vendor })
    }
    return out
  }

  // ---- live --------------------------------------------------------------
  readonly property real vramPct: {
    var p = Model.gpuVramPct(live)
    return p === null ? -1 : p
  }
  // A current or retained measurement establishes that this card reports a
  // percentage. Retained history prevents a failed poll from adding/removing
  // a plot; Store resets that history when the selected hardware changes.
  readonly property bool vramSeriesAvailable: vramPct >= 0 || [
    model ? model.gpuHistory : [], model ? model.gpuLong : []
  ].some(function (points) {
    return Array.isArray(points) && points.some(function (point) { return Model.graphValue(point, "v") !== null })
  })
  readonly property string vramText: {
    if (!live) return "--"
    if (vendor === "nvidia") {
      var used = Model.nvidiaMiBToBytes(live.memUsedM)
      var total = Model.nvidiaMiBToBytes(live.memTotalM)
      if (used === null) return "--"
      if (total === null) return Model.formatBytes(used)
      return Model.formatBytes(used) + " of " + Model.formatBytes(total)
    }
    if (live.vramUsed === null || live.vramUsed === undefined) return "--"
    if (live.vramTotal === null || live.vramTotal === undefined) return Model.formatBytes(live.vramUsed)
    return Model.formatBytes(live.vramUsed) + " of " + Model.formatBytes(live.vramTotal)
  }
  readonly property string tempText: {
    if (!live || live.tempC === null || live.tempC === undefined) return "--"
    var unit = model && model.cfg ? model.cfg.temperatureUnit : "celsius"
    var t = Model.formatTemp(live.tempC, unit)
    if (live.tempJunctionC !== null && live.tempJunctionC !== undefined) t += " · " + Model.formatTemp(live.tempJunctionC, unit) + " junction"
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
    spacing: Commons.Style.space(12)

    Components.Hero {
      width: parent.width
      detailsTarget: root
      visible: root.vendor !== ""
      title: root.gpuTitle
      meta: root.gpuMeta
    }

    Components.DeviceChoices {
      width: parent.width
      visible: root.cardOptions.length > 1
      options: root.cardOptions
      value: root.gpu ? root.gpu.card : ""
      fontSize: Commons.Style.font.caption
      onChanged: function (value) { if (root.model) root.model.selectGpu(value) }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.nvidiaError !== ""
      text: root.nvidiaError
      color: Commons.Color.urgent
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Components.AdaptiveColumns {
      objectName: "resourceColumns"
      width: parent.width
      primary: [
        Components.SectionCard {
          width: parent.width
          title: "GPU activity"

          Components.MetricReadout {
            width: parent.width
            value: root.display ? (root.display.estimated ? "~" : "") + Model.formatPct(root.display.pct, 1) : "--"
            hint: root.display && root.display.estimated ? "Frequency estimate · not measured busy time" : "Busy · per card"
          }

          Components.GraphBlock {
            objectName: "gpuHistory"
            width: parent.width
            title: "HISTORY"
            finePoints: root.model ? root.model.gpuHistory : []
            longPoints: root.model ? root.model.gpuLong : []
            longWindow: root.longWindow
            sampleSeconds: root.model ? root.model.barIntervalMs / 1000 : 1
            graphLayout: root.model && root.model.cfg ? root.model.cfg.gpuGraphLayout : "overlay"
            fixedMax: 100
            fields: {
              var out = [{ key: "b", label: root.display && root.display.estimated ? "freq estimate" : "busy", color: root.pal.primary }]
              if (root.vramSeriesAvailable) out.push({ key: "v", label: "VRAM", color: root.pal.secondary })
              return out
            }
            legend: [
              { label: root.display && root.display.estimated ? "freq estimate" : "busy", color: root.pal.primary, value: root.display ? (root.display.estimated ? "~" : "") + Model.formatPct(root.display.pct) : "--" },
              { label: "VRAM", color: root.pal.secondary, value: root.vramPct < 0 ? "--" : Model.formatPct(root.vramPct), visible: root.vramSeriesAvailable }
            ]
            onToggleWindow: if (root.panel) root.panel.longWindow = !root.panel.longWindow
          }
        },
        Components.SectionCard {
          width: parent.width
          title: root.live && root.live.memKind === "shared" ? "Shared memory" : "Video memory"

          Components.MetricReadout {
            width: parent.width
            value: root.vramText
            hint: root.vramPct >= 0 ? Model.formatPct(root.vramPct) + " used" : "Resident bytes · capacity unavailable"
          }

          Components.CompositionBar {
            width: parent.width
            visible: root.vramPct >= 0
            segments: [{ fraction: root.vramPct / 100, color: root.pal.secondary }]
          }
        }
      ]
      secondary: [
        Components.SectionCard {
          width: parent.width

          Components.ProcessList {
            id: processRoster
            panel: root.panel
            active: root.active
            scopeText: "Top processes with readable GPU attribution; full-roster search is unavailable."
            width: parent.width
            rows: root.rows
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
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
        },
        Components.SectionCard {
          width: parent.width
          title: "Device"
          id: deviceDetails
          readonly property bool hasMemoryClock: !!(root.live && root.live.memoryClockSource !== undefined && root.live.memoryClockSource !== "")

          Components.StatRow { width: parent.width; wrapValue: true; label: "Temperature"; value: root.tempText }

          Components.StatRow { width: parent.width; wrapValue: true; label: "GPU power"; value: root.live ? Model.formatWatts(root.live.powerW) : "--"; visible: root.vendor !== "intel" }

          Components.StatRow {
            wrapValue: true
            width: parent.width
            label: root.vendor === "intel" ? "Frequency" : "Core clock"
            value: root.clockText
          }
          Components.StatRow {
            wrapValue: true
            objectName: "gpuMemoryClock"
            width: parent.width
            visible: deviceDetails.hasMemoryClock
            label: "Memory clock"
            value: Model.formatGpuClock(root.live ? root.live.memoryClockMhz : null)
          }
          Components.StatRow {
            wrapValue: true
            width: parent.width
            visible: root.vendor === "amd" && root.live && root.live.memBusy !== null && root.live.memBusy !== undefined
            label: "Memory busy"
            value: root.live ? Model.formatPct(root.live.memBusy, 1) : "--"
          }
          Repeater {
            model: root.live && root.live.engines ? root.live.engines : []
            delegate: Components.StatRow {
              wrapValue: true
              required property var modelData
              width: parent.width
              label: String(modelData.id || "")
              value: Model.formatPct(modelData.busy, 1)
            }
          }

          Components.Disclosure {
            width: parent.width
            title: "Device details"
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              color: root.pal.dim
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              text: root.gpuMeta
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              color: root.pal.dim
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              text: root.gpu ? String(root.gpu.deviceId || root.gpu.slot || root.gpu.pciId || "") : ""
              visible: text !== ""
            }
          }
        }
      ]
    }
  }
}
