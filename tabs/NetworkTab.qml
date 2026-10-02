import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "../components" as Components

// Network tab: interface identity (type, link speed, addresses), an
// interface picker, down/up history, totals, and per-process TCP
// attribution with a sticky roster. Bytes that cannot be assigned to a
// visible process (other users' sockets, UDP, closed-socket remainder)
// are an honest "Other traffic" row — never dropped, never misattributed.
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "net"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var sample: model ? model.sample : null
  readonly property string ifname: model ? model.effectiveInterface : ""
  readonly property var ifaceRates: model ? model.ifaceRates : null
  readonly property string interfaceError: model ? model.networkInterfaceError : ""
  readonly property bool interfaceValid: ifname !== "" && interfaceError === ""
  readonly property bool pinned: model ? model.pinnedInterface : false
  readonly property string unit: model ? model.rateUnit : "bytes"
  readonly property var netInfo: model && model.sysInfo && model.sysInfo.net ? model.sysInfo.net : null
  readonly property var iface: netInfo && netInfo.byName ? (netInfo.byName[ifname] || null) : null
  readonly property var pal: Model.seriesPalette(String(Color.accent), String(Color.urgent), String(Color.foreground), String(Color.background))

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (active && model) model.pollNet()
  }

  function rate(v) { return Model.formatRateUnit(v, root.unit) }

  // ---- identity ----------------------------------------------------------
  readonly property string netTitle: ifname !== "" ? ifname : "Network"
  readonly property string netMeta: {
    if (iface) return Model.interfaceSummary(iface)
    if (ifname === "") return "No default route"
    return pinned ? "Pinned interface" : "Default route"
  }
  readonly property string netDetail: {
    if (iface && iface.operstate && iface.operstate !== "up" && iface.operstate !== "unknown") return iface.operstate
    return ""
  }
  readonly property var interfaceOptions: {
    var out = [{ value: "auto", label: "auto", tooltip: "Follow the default route" }]
    var seen = {}
    var list = sample && sample.net ? sample.net : []
    for (var i = 0; i < list.length; i++) {
      var n = list[i].n
      if (!n || seen[n]) continue
      var meta = netInfo && netInfo.byName ? netInfo.byName[n] : null
      if (meta && meta.virtual && n !== ifname) continue
      seen[n] = true
      out.push({ value: n, label: n, tooltip: meta ? Model.interfaceSummary(meta) : n })
    }
    return out
  }
  readonly property var totals: {
    if (!sample || !sample.net || ifname === "") return null
    for (var i = 0; i < sample.net.length; i++)
      if (sample.net[i].n === ifname) return { rx: sample.net[i].rx, tx: sample.net[i].tx }
    return null
  }

  // ---- rows --------------------------------------------------------------
  readonly property var rows: {
    var src = model ? model.netRows : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      out.push({ pid: src[i].pid, comm: src[i].comm, history: src[i].history, sortKey: src[i].sortKey,
                 valueText: "↓ " + root.rate(src[i].rx) + "  ↑ " + root.rate(src[i].tx) })
    }
    return out
  }
  readonly property string errorText: model ? model.netError : ""
  readonly property bool attributionEmpty: {
    var list = rows || []
    var live = 0, other = 0
    for (var i = 0; i < list.length; i++) {
      if (list[i].pid === 0) other += Number(list[i].sortKey) || 0
      else if ((Number(list[i].sortKey) || 0) > 1) live++
    }
    return list.length > 0 && live === 0 && other >= 64
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(10)

    Components.Hero {
      width: parent.width
      title: root.netTitle
      meta: root.netMeta
      detail: root.netDetail
    }

    Text {
      textFormat: Text.PlainText
      visible: root.interfaceError !== ""
      text: root.interfaceError
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    ButtonGroup {
      visible: root.interfaceOptions.length > 2
      options: root.interfaceOptions
      value: root.pinned ? (root.model ? root.model.networkInterface : "auto") : "auto"
      fontSize: Style.font.caption
      onChanged: function (value) { if (root.model) root.model.selectInterface(value) }
    }

    Components.GraphBlock {
      width: parent.width
      title: "TRAFFIC"
      finePoints: root.model ? root.model.netHistory : []
      longPoints: root.model ? root.model.netLong : []
      longWindow: root.longWindow
      sampleSeconds: root.model ? root.model.barIntervalMs / 1000 : 1
      formatValue: function (v) { return root.rate(v) }
      fields: [
        { key: "rx", label: "down", color: root.pal.primary },
        { key: "tx", label: "up", color: root.pal.secondary }
      ]
      legend: [
        { label: "down", color: root.pal.primary, value: root.ifaceRates ? root.rate(root.ifaceRates.rxBps) : "--" },
        { label: "up", color: root.pal.secondary, value: root.ifaceRates ? root.rate(root.ifaceRates.txBps) : "--" }
      ]
      onToggleWindow: if (root.panel) root.panel.longWindow = !root.panel.longWindow
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Components.StatRow {
        width: parent.width
        visible: root.totals !== null
        label: "Received / sent"
        value: root.totals ? Model.formatBytes(root.totals.rx) + " / " + Model.formatBytes(root.totals.tx) : "--"
      }
      Components.StatRow {
        width: parent.width
        visible: root.iface && root.iface.mac !== ""
        label: "MAC"
        value: root.iface ? root.iface.mac : ""
      }
      Components.StatRow {
        width: parent.width
        visible: root.iface && root.iface.addrs.length > 2
        label: "Addresses"
        value: root.iface ? root.iface.addrs.join("  ") : ""
      }
    }

    PanelSeparator { }

    Components.ProcessList {
      width: parent.width
      rows: root.rows
      cursorIndex: root.panel ? root.panel.cursorIndex : -1
      cursorActive: root.panel ? root.panel.cursorActive === true : false
      onRowHovered: function (index, on) { if (root.panel && root.panel.hoverRow) root.panel.hoverRow(index, on) }
      valueHeader: "TRAFFIC"
      emptyText: root.active ? (root.interfaceValid ? "Sampling…" : "No interface to watch") : "Open this tab to sample processes"
      errorText: root.errorText
    }

    Text {
      textFormat: Text.PlainText
      visible: root.attributionEmpty
      text: "Traffic is moving, but no TCP socket of yours carried it this interval (UDP, or other users' sockets)."
      color: root.pal.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
