import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "../components" as Components

// Memory tab: PSI pressure ring + RAM composition ring, breakdown rows,
// swap totals and rates, and the top-by-RSS process roster.
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "mem"
  readonly property var sample: model ? model.sample : null
  readonly property var comp: model ? model.memComp : null
  readonly property var swap: sample ? Model.swapUsage(sample.mem) : null
  readonly property var swapRate: model ? model.swapRate : null
  readonly property var sysMem: model && model.sysInfo ? model.sysInfo.mem : null
  readonly property var sysHost: model && model.sysInfo ? model.sysInfo.host : null

  property var rows: []
  property string errorText: ""

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (!active) return
    if (model && model.refreshSysInfo) model.refreshSysInfo()
    if (proc.running) return
    watchdog.restart()
    proc.running = true
  }

  readonly property string memTitle: {
    if (comp) return Model.formatKiB(comp.totalK) + " installed"
    return "Memory"
  }

  readonly property string memMeta: {
    var m = sysMem
    if (m && m.zram && m.zram.length > 0) {
      var z = m.zram[0]
      var bits = [z.dev]
      if (z.alg) bits.push(z.alg)
      if (z.diskBytes) bits.push(Model.formatBytes(z.diskBytes))
      return bits.join(" · ")
    }
    if (m && m.swaps && m.swaps.length > 0) {
      var s = m.swaps[0]
      var parts = [s.kind]
      if (s.file) parts.push(s.file)
      if (s.sizeKb) parts.push(Model.formatKiB(s.sizeKb))
      return parts.join(" · ")
    }
    if (swap && swap.totalK <= 0) return "no swap"
    return ""
  }

  readonly property var swapDeviceRows: {
    var out = []
    var m = sysMem
    var zramByDev = {}
    var i
    if (m && m.zram) {
      for (i = 0; i < m.zram.length; i++) zramByDev[m.zram[i].dev] = m.zram[i]
    }
    if (m && m.swaps) {
      for (i = 0; i < m.swaps.length; i++) {
        var sw = m.swaps[i]
        var label = sw.kind
        var value = sw.file
        if (sw.kind === "zram") {
          var base = sw.file.replace(/^.*\//, "")
          var z = zramByDev[base]
          label = base || "zram"
          var bits = []
          if (z && z.alg) bits.push(z.alg)
          bits.push(Model.formatKiB(sw.sizeKb))
          value = bits.join(" · ")
        } else {
          value = (sw.file ? sw.file + " · " : "") + Model.formatKiB(sw.sizeKb)
        }
        out.push({ label: label, value: value })
      }
    }
    return out
  }

  readonly property string hostLine: {
    var h = sysHost
    if (!h) return ""
    var parts = []
    if (h.sysVendor && h.productName) parts.push(h.sysVendor + " " + h.productName)
    else if (h.productName) parts.push(h.productName)
    else if (h.sysVendor) parts.push(h.sysVendor)
    if (h.kernel) parts.push("Linux " + h.kernel)
    return parts.join(" · ")
  }

  function apply(text) {
    var env = Model.safeJson(text)
    if (!env || env.ok !== true) {
      errorText = "process sampler failed: " + ((env && env.error) ? String(env.error) : "bad output")
      return
    }
    var totalK = root.sample ? root.sample.mem.tot : 0
    var parsed = Model.parsePs(env.payload, panel ? panel.processCount : 5)
    var mapped = []
    for (var i = 0; i < parsed.length; i++) {
      var pct = totalK > 0 ? 100 * parsed[i].value / totalK : null
      mapped.push({
        pid: parsed[i].pid,
        comm: parsed[i].comm,
        valueText: pct === null ? "--" : Model.formatPct(pct, 1),
        sortKey: parsed[i].value
      })
    }
    rows = Model.mergeRoster(rows, mapped, panel ? panel.processCount : 5)
    errorText = ""
  }

  Process {
    id: proc
    command: [root.model ? root.model.localPath("scripts/process-memory") : "process-memory",
              String(root.panel ? root.panel.processCount : 5)]
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
      title: root.memTitle
      meta: root.memMeta
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Row {
      width: parent.width
      spacing: Style.space(18)

      Components.RingGauge {
        // PSI memory "some" avg10 as pressure; absent PSI reads as no data.
        readonly property var psi: root.sample ? root.sample.psi : null
        fraction: psi && psi.ms10 !== null && psi.ms10 !== undefined ? Math.min(1, psi.ms10 / 100) : 0
        color: Theme.series.swap
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: psi && psi.ms10 !== null && psi.ms10 !== undefined ? Model.formatPct(psi.ms10, 1) : "--"
        subText: "pressure"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }

      Components.RingGauge {
        readonly property var c: root.comp
        segments: c ? [
          { fraction: c.totalK > 0 ? c.appsK / c.totalK : 0, color: Theme.series.memApps },
          { fraction: c.totalK > 0 ? c.cacheK / c.totalK : 0, color: Theme.series.memCache },
          { fraction: c.totalK > 0 ? c.kernelK / c.totalK : 0, color: Theme.series.memKernel },
          { fraction: c.totalK > 0 ? c.freeK / c.totalK : 0, color: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc") }
        ] : []
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: c ? Model.formatPct(c.usedPct) : "--"
        subText: "RAM"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        spacing: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
          model: [
            { label: "Applications", color: Theme.series.memApps, kib: root.comp ? root.comp.appsK : null },
            { label: "Cache", color: Theme.series.memCache, kib: root.comp ? root.comp.cacheK : null },
            { label: "Kernel", color: Theme.series.memKernel, kib: root.comp ? root.comp.kernelK : null },
            { label: "Free", color: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc"), kib: root.comp ? root.comp.freeK : null }
          ]

          delegate: Row {
            required property var modelData
            spacing: Style.space(6)

            Rectangle {
              width: Style.space(8)
              height: Style.space(8)
              radius: 2
              color: parent.modelData.color
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: parent.modelData.label + "  " + (parent.modelData.kib === null ? "--" : Model.formatKiB(parent.modelData.kib))
              color: root.panel ? root.panel.barForeground : "#cacccc"
              font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }

    Components.StatRow {
      width: parent.width
      label: "Used"
      value: root.comp
             ? Model.formatKiB(root.comp.usedK) + " of " + Model.formatKiB(root.comp.totalK)
             : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Swap"
      value: {
        if (!root.swap) return "--"
        if (root.swap.totalK <= 0) return "none"
        return Model.formatKiB(root.swap.usedK) + " of " + Model.formatKiB(root.swap.totalK)
      }
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Swap in/out"
      visible: root.swap !== null && root.swap.totalK > 0
      value: root.swapRate
             ? Model.formatRate(root.swapRate.inKBs * 1024) + " / " + Model.formatRate(root.swapRate.outKBs * 1024)
             : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Repeater {
      model: root.swapDeviceRows

      delegate: Components.StatRow {
        required property var modelData
        width: column.width
        label: String(modelData.label || "Swap")
        value: String(modelData.value || "--")
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.hostLine !== ""
      text: root.hostLine
      color: root.panel ? Qt.darker(root.panel.barForeground, 1.6) : "#cacccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    PanelSeparator {
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
    }

    Components.ProcessList {
      width: parent.width
      rows: root.rows
      valueHeader: "% OF RAM"
      emptyText: root.active ? "Sampling…" : "Open this tab to sample processes"
      errorText: root.errorText
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }
  }
}
