import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "../components" as Components

// CPU tab: 60s stacked user/system/iowait history, machine stat rows, and
// the top-by-CPU process roster (sampled on demand while the tab is open).
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "cpu"
  readonly property var sample: model ? model.sample : null
  readonly property var cpuPct: model ? model.cpuPct : null
  readonly property var sysCpu: model && model.sysInfo ? model.sysInfo.cpu : null
  readonly property var cpuFreqMhz: model ? model.cpuFreqMhz : null

  property var rows: []
  property string errorText: ""

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function scriptPath(name) {
    return model ? model.localPath("scripts/" + name) : name
  }

  function refresh() {
    if (!active) return
    if (model && model.refreshSysInfo) model.refreshSysInfo()
    if (proc.running) return
    watchdog.restart()
    proc.running = true
  }

  readonly property string cpuMeta: {
    var c = sysCpu
    if (!c) return ""
    var parts = []
    if (c.physCores) parts.push(c.physCores + " cores")
    if (c.threads && c.threads !== c.physCores) parts.push(c.threads + " threads")
    else if (c.threads && !c.physCores) parts.push(c.threads + " threads")
    if (c.cacheKb) parts.push(Model.formatCache(c.cacheKb) + " L3")
    return parts.join(" · ")
  }

  readonly property string cpuDetail: {
    if (cpuFreqMhz !== null && cpuFreqMhz !== undefined) return Model.formatMhz(cpuFreqMhz)
    if (sysCpu && sysCpu.governor) return sysCpu.governor
    return ""
  }

  readonly property string cpuFreqValue: {
    var cur = cpuFreqMhz
    if (cur === null || cur === undefined) cur = sysCpu ? sysCpu.mhzNow : null
    var max = sysCpu ? sysCpu.maxMhz : null
    if (cur === null && max === null) return ""
    if (max === null) return Model.formatMhz(cur)
    return Model.formatMhz(cur) + " / " + Model.formatMhz(max)
  }

  function apply(text) {
    var env = Model.safeJson(text)
    if (!env || env.ok !== true) {
      // Helper failure is a visible error, never an empty "no activity" list.
      errorText = "process sampler failed: " + ((env && env.error) ? String(env.error) : "bad output")
      return
    }
    var parsed = Model.parsePs(env.payload, panel ? panel.processCount : 5)
    var mapped = []
    for (var i = 0; i < parsed.length; i++) {
      mapped.push({
        pid: parsed[i].pid,
        comm: parsed[i].comm,
        valueText: Model.formatPct(parsed[i].value, 1),
        sortKey: parsed[i].value
      })
    }
    rows = Model.mergeRoster(rows, mapped, panel ? panel.processCount : 5)
    errorText = ""
  }

  Process {
    id: proc
    command: [root.scriptPath("process-cpu"), String(root.panel ? root.panel.processCount : 5)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
    onExited: function(exitCode, exitStatus) {
      watchdog.stop()
      if (exitCode !== 0 && root.errorText === "")
        root.errorText = "process sampler exited with code " + exitCode
    }
  }

  Timer {
    id: cadence
    interval: root.panel ? root.panel.panelIntervalMs : 2000
    repeat: true
    running: root.active
    onTriggered: root.refresh()
  }

  Timer {
    id: watchdog
    interval: Math.max(6000, (root.panel ? root.panel.panelIntervalMs : 2000) * 3)
    repeat: false
    onTriggered: {
      if (proc.running) {
        proc.signal(9)
        root.errorText = "process sampler timed out"
      }
    }
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    Components.HardwareHero {
      width: parent.width
      visible: root.sysCpu && root.sysCpu.modelName !== ""
      title: root.sysCpu ? root.sysCpu.modelName : ""
      meta: root.cpuMeta
      detail: root.cpuDetail
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.HistoryGraph {
      width: parent.width
      stacked: true
      fixedMax: 100
      capacity: root.model ? root.model.historyLimit : 60
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      gridColor: Theme.gridFor(root.panel ? root.panel.barForeground : "#cacccc")
      series: [
        { label: "user", color: Theme.series.cpuUser, values: (root.model ? root.model.cpuHistory : []).map(function (p) { return p.u }) },
        { label: "system", color: Theme.series.cpuSystem, values: (root.model ? root.model.cpuHistory : []).map(function (p) { return p.s }) },
        { label: "iowait", color: Theme.series.cpuIowait, values: (root.model ? root.model.cpuHistory : []).map(function (p) { return p.io }) }
      ]
    }

    // legend
    Row {
      spacing: Style.space(10)

      Repeater {
        model: [
          { label: "user", color: Theme.series.cpuUser, pct: root.cpuPct ? root.cpuPct.user : null },
          { label: "system", color: Theme.series.cpuSystem, pct: root.cpuPct ? root.cpuPct.system : null },
          { label: "iowait", color: Theme.series.cpuIowait, pct: root.cpuPct ? root.cpuPct.iowait : null },
          { label: "steal", color: Theme.series.cpuSteal, pct: root.cpuPct ? root.cpuPct.steal : null }
        ]

        delegate: Row {
          required property var modelData
          spacing: Style.space(4)

          Rectangle {
            width: Style.space(8)
            height: Style.space(8)
            radius: 2
            color: parent.modelData.color
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: parent.modelData.label + " " + (parent.modelData.pct === null ? "--" : Model.formatPct(parent.modelData.pct))
            color: root.panel ? Qt.darker(root.panel.barForeground, 1.3) : "#cacccc"
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    Components.StatRow {
      width: parent.width
      label: "Vendor"
      visible: root.sysCpu && root.sysCpu.vendorId !== ""
      value: root.sysCpu ? Model.cpuVendorLabel(root.sysCpu.vendorId) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Frequency"
      visible: root.cpuFreqValue !== ""
      value: root.cpuFreqValue
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Governor"
      visible: root.sysCpu && root.sysCpu.governor !== ""
      value: root.sysCpu ? root.sysCpu.governor : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Temperature"
      value: root.sample ? Model.formatTemp(root.sample.tempC) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Load average"
      value: root.sample
             ? Model.formatLoad(root.sample.load[0]) + "  " + Model.formatLoad(root.sample.load[1]) + "  " + Model.formatLoad(root.sample.load[2])
             : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Uptime"
      value: root.sample ? Model.formatUptime(root.sample.uptimeS) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Cores"
      value: root.sample ? String(root.sample.cores) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    PanelSeparator {
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
    }

    Components.ProcessList {
      width: parent.width
      rows: root.rows
      valueHeader: "CPU"
      emptyText: root.active ? "Sampling…" : "Open this tab to sample processes"
      errorText: root.errorText
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }
  }
}
