import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "../components" as Components

// CPU tab: identity, stacked user/system/iowait/steal history, the core
// grid, machine stats, the integrated GPU (when there is one) and the
// top-by-CPU roster. Every number comes from the store; this file lays
// it out.
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "cpu"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var sample: model ? model.sample : null
  readonly property var cpuPct: model ? model.cpuPct : null
  readonly property var sysCpu: model && model.sysInfo ? model.sysInfo.cpu : null
  readonly property var cpuFreqMhz: model ? model.cpuFreqMhz : null
  readonly property var pal: Model.seriesPalette(String(Color.accent), String(Color.urgent), String(Color.foreground), String(Color.background))

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (active && model) model.pollProcesses()
  }

  // ---- identity ----------------------------------------------------------
  readonly property string cpuTitle: {
    if (sysCpu && sysCpu.modelName) return Model.cleanCpuName(sysCpu.modelName)
    return "CPU"
  }
  readonly property string cpuMeta: {
    var c = sysCpu
    if (!c) return ""
    var parts = []
    if (c.physCores) parts.push(c.physCores + " cores")
    if (c.threads && c.threads !== c.physCores) parts.push(c.threads + " threads")
    else if (c.threads && !c.physCores) parts.push(c.threads + " threads")
    var mix = Model.formatCpuClassMix(c.classes)
    if (mix) parts.push(mix)
    if (c.cacheKb) parts.push(Model.formatCache(c.cacheKb) + " L3")
    return parts.join(" · ")
  }
  readonly property string cpuDetail: {
    if (cpuFreqMhz !== null && cpuFreqMhz !== undefined) return Model.formatMhz(cpuFreqMhz)
    if (sysCpu && sysCpu.governor) return sysCpu.governor
    return ""
  }
  readonly property string hostLine: model && model.sysInfo ? Model.hostLine(model.sysInfo.host) : ""
  readonly property string cpuFreqValue: {
    var cur = cpuFreqMhz
    if (cur === null || cur === undefined) cur = sysCpu ? sysCpu.mhzNow : null
    var max = sysCpu ? sysCpu.maxMhz : null
    if (cur === null && max === null) return ""
    if (max === null) return Model.formatMhz(cur)
    return Model.formatMhz(cur) + " / " + Model.formatMhz(max)
  }
  readonly property int coreCount: sample ? sample.cores : (sysCpu && sysCpu.threads ? sysCpu.threads : 1)
  readonly property bool loadHot: sample && sample.load[0] !== null && sample.load[0] > coreCount
  readonly property string pressureText: {
    var p = sample ? sample.psi : null
    if (!p || p.cs10 === null) return ""
    var bits = [Model.formatPct(p.cs10, 1) + " some"]
    if (p.cf10 !== null) bits.push(Model.formatPct(p.cf10, 1) + " full")
    return bits.join(" · ")
  }

  // ---- rows --------------------------------------------------------------
  readonly property var rows: {
    var src = model ? model.cpuRows : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      out.push({ pid: src[i].pid, comm: src[i].comm, history: src[i].history,
                 valueText: Model.formatPct(src[i].value, 1), sortKey: src[i].sortKey,
                 hint: Model.formatPct(src[i].core, 0) + " of one core" })
    }
    return out
  }
  readonly property string errorText: model ? model.procError : ""
  readonly property string procFooter: {
    var s = model ? model.procStats : null
    if (!s) return ""
    return s.procs + " processes · " + s.running + " running · " + s.threads + " threads"
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(10)

    Components.Hero {
      width: parent.width
      title: root.cpuTitle
      meta: root.cpuMeta
      detail: root.cpuDetail
    }

    Text {
      textFormat: Text.PlainText
      visible: root.hostLine !== ""
      text: root.hostLine
      color: root.pal.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      elide: Text.ElideRight
    }

    Components.GraphBlock {
      width: parent.width
      title: "LOAD"
      finePoints: root.model ? root.model.cpuHistory : []
      longPoints: root.model ? root.model.cpuLong : []
      longWindow: root.longWindow
      stacked: true
      fixedMax: 100
      fields: [
        { key: "u", label: "user", color: root.pal.primary },
        { key: "s", label: "system", color: root.pal.secondary },
        { key: "io", label: "iowait", color: root.pal.tertiary },
        { key: "st", label: "steal", color: root.pal.hot }
      ]
      legend: [
        { label: "user", color: root.pal.primary, value: root.cpuPct ? Model.formatPct(root.cpuPct.user) : "--" },
        { label: "system", color: root.pal.secondary, value: root.cpuPct ? Model.formatPct(root.cpuPct.system) : "--" },
        { label: "iowait", color: root.pal.tertiary, value: root.cpuPct ? Model.formatPct(root.cpuPct.iowait) : "--" },
        { label: "steal", color: root.pal.hot, value: root.cpuPct ? Model.formatPct(root.cpuPct.steal) : "--",
          visible: root.cpuPct !== null && root.cpuPct.steal > 0 }
      ]
      onToggleWindow: if (root.panel) root.panel.longWindow = !root.panel.longWindow
    }

    Components.CoreGrid {
      width: parent.width
      layout: Model.coreGridLayout(
        root.sysCpu && root.sysCpu.topo ? root.sysCpu.topo : [],
        root.model && root.model.coreUsage ? root.model.coreUsage : {}
      )
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Components.StatRow {
        width: parent.width
        visible: root.cpuFreqValue !== ""
        label: "Frequency"
        value: root.cpuFreqValue
      }
      Components.StatRow {
        width: parent.width
        visible: root.sysCpu && root.sysCpu.governor !== ""
        label: "Governor"
        value: root.sysCpu ? root.sysCpu.governor : "--"
      }
      Components.StatRow {
        width: parent.width
        label: "Temperature"
        value: root.sample ? Model.formatTemp(root.sample.tempC) : "--"
      }
      Components.StatRow {
        width: parent.width
        visible: root.pressureText !== ""
        label: "Pressure"
        value: root.pressureText
      }
      Components.StatRow {
        width: parent.width
        label: "Load average"
        value: root.sample
               ? Model.formatLoad(root.sample.load[0]) + "  " + Model.formatLoad(root.sample.load[1]) + "  " + Model.formatLoad(root.sample.load[2])
               : "--"
        valueColor: root.loadHot ? Color.urgent : Color.foreground
      }
      Components.StatRow {
        width: parent.width
        label: "Uptime"
        value: root.sample ? Model.formatUptime(root.sample.uptimeS) : "--"
      }
    }

    Components.GpuCard {
      width: parent.width
      gpu: root.model ? root.model.integratedGpu : null
      gpuInfo: {
        if (!root.model || !root.model.sysInfo || !root.model.sysInfo.gpusByCard) return null
        var g = root.model.integratedGpu
        if (!g) return null
        return root.model.sysInfo.gpusByCard[g.card] || g
      }
      live: root.model ? root.model.integratedGpuLive : null
      errorText: root.model ? String(root.model.integratedGpuError || "") : ""
    }

    PanelSeparator { }

    Components.ProcessList {
      width: parent.width
      rows: root.rows
      valueHeader: "CPU"
      emptyText: root.active ? "Sampling…" : "Open this tab to sample processes"
      errorText: root.errorText
    }

    Text {
      textFormat: Text.PlainText
      visible: root.procFooter !== ""
      text: root.procFooter
      color: root.pal.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.features: ({ "tnum": 1 })
    }
  }
}
