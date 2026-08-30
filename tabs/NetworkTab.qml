import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "../components" as Components

// Network tab: interface rates, 60s dual-series history, and per-process
// TCP attribution with a sticky roster. Bytes that cannot be assigned to a
// visible process (other users' sockets, UDP, closed-socket remainder) are
// reported as an honest "Other traffic" row keyed on pid 0 — never dropped,
// never misattributed.
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "net"
  readonly property string ifname: model ? model.effectiveInterface : ""
  readonly property var ifaceRates: model ? model.ifaceRates : null

  property var rows: []
  property string errorText: ""
  property var prevSockets: null
  property var prevIf: null
  property real prevTs: 0

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()
  onIfnameChanged: {
    prevSockets = null
    prevIf = null
    prevTs = 0
    rows = []
    if (active) refresh()
  }

  function refresh() {
    if (!active) return
    if (ifname === "") return
    if (proc.running) return
    watchdog.restart()
    proc.running = true
  }

  function apply(text) {
    var env = Model.safeJson(text)
    if (!env || env.ok !== true) {
      errorText = "network sampler failed: " + ((env && env.error) ? String(env.error) : "bad output")
      return
    }
    var sockets = Model.parseSs(env.payload)
    var currIf = { rx: env.ifRx, tx: env.ifTx }
    var dt = prevTs > 0 ? env.ts - prevTs : 0
    var result = Model.computeNetAppRows(prevSockets, sockets, prevIf, currIf, dt, env.addrs)

    var limit = panel ? panel.processCount : 5
    var mapped = []
    for (var i = 0; i < result.rows.length; i++) {
      var r = result.rows[i]
      mapped.push({
        pid: r.pid,
        comm: r.comm,
        valueText: "↓ " + Model.formatRate(r.rxBps) + "  ↑ " + Model.formatRate(r.txBps),
        sortKey: r.sortKey
      })
    }
    // The catch-all row is keyed strictly on pid 0; a process literally
    // named "Other traffic" keeps its own pid and cannot collide with it.
    mapped.push({
      pid: 0,
      comm: "",
      valueText: "↓ " + Model.formatRate(result.other.rxBps) + "  ↑ " + Model.formatRate(result.other.txBps),
      sortKey: result.other.rxBps + result.other.txBps
    })
    rows = Model.mergeRoster(rows, mapped, limit + 1)

    prevSockets = sockets
    prevIf = currIf
    prevTs = env.ts
    errorText = ""
  }

  Process {
    id: proc
    command: [root.model ? root.model.localPath("scripts/process-net") : "process-net", root.ifname]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
    onExited: function(exitCode, exitStatus) {
      watchdog.stop()
      if (exitCode !== 0 && root.errorText === "")
        root.errorText = "network sampler exited with code " + exitCode
    }
  }

  Timer {
    id: cadence
    interval: root.panel ? root.panel.panelIntervalMs : 2000
    repeat: true
    running: root.active && root.ifname !== ""
    onTriggered: root.refresh()
  }

  Timer {
    id: watchdog
    interval: Math.max(7000, (root.panel ? root.panel.panelIntervalMs : 2000) * 3)
    repeat: false
    onTriggered: {
      if (proc.running) {
        proc.signal(9)
        root.errorText = "network sampler timed out"
      }
    }
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    Components.StatRow {
      width: parent.width
      label: "Interface"
      value: root.ifname !== "" ? root.ifname : "none"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Down / Up"
      value: root.ifaceRates
             ? Model.formatRate(root.ifaceRates.rxBps) + " / " + Model.formatRate(root.ifaceRates.txBps)
             : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      valueBold: true
    }

    Components.HistoryGraph {
      width: parent.width
      capacity: root.model ? root.model.historyLimit : 60
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      gridColor: Theme.gridFor(root.panel ? root.panel.barForeground : "#cacccc")
      series: [
        { label: "down", color: Theme.series.netRx, values: (root.model ? root.model.netHistory : []).map(function (p) { return p.rx }) },
        { label: "up", color: Theme.series.netTx, values: (root.model ? root.model.netHistory : []).map(function (p) { return p.tx }) }
      ]
    }

    Row {
      spacing: Style.space(10)

      Repeater {
        model: [
          { label: "down", color: Theme.series.netRx },
          { label: "up", color: Theme.series.netTx }
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
            text: parent.modelData.label
            color: root.panel ? Qt.darker(root.panel.barForeground, 1.3) : "#cacccc"
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    PanelSeparator {
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
    }

    Components.ProcessList {
      width: parent.width
      rows: root.rows
      valueHeader: "NET"
      emptyText: root.ifname === "" ? "No network interface" : (root.active ? "Sampling…" : "Open this tab to sample")
      errorText: root.errorText
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    // The interface choice is documented where the user sees the numbers.
    Text {
      textFormat: Text.PlainText
      visible: root.ifname !== ""
      text: {
        var pinned = root.model && root.model.networkInterface
          && root.model.networkInterface !== "auto" && root.model.networkInterface !== ""
        var head = pinned
          ? ("Pinned interface " + root.ifname + ".")
          : ("Default route via " + root.ifname + " (lowest metric across IPv4/IPv6; IPv4 wins ties).")
        return head + " TCP attribution is scoped to this interface's addresses. UDP and sockets not owned by this user appear as Other traffic."
      }
      color: root.panel ? Qt.darker(root.panel.barForeground, 1.6) : "#cacccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
