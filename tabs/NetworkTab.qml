import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model
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
  readonly property string interfaceError: model ? model.networkInterfaceError : ""
  readonly property bool interfaceValid: ifname !== "" && interfaceError === ""

  readonly property var rows: {
    var src = model ? model.netRows : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      out.push({ pid: src[i].pid, comm: src[i].comm,
                 valueText: "↓ " + Model.formatRate(src[i].rx) + "  ↑ " + Model.formatRate(src[i].tx),
                 sortKey: src[i].sortKey })
    }
    return out
  }
  readonly property string errorText: model ? model.netError : ""

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (!active || !interfaceValid) return
    if (model) model.pollNet()
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      visible: root.interfaceError !== ""
      text: root.interfaceError
      color: Color.urgent
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      width: parent.width
      wrapMode: Text.WordWrap
    }

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
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      points: root.model ? root.model.netHistory : []
      fields: [
        { key: "rx", label: "down", color: Theme.series.netRx },
        { key: "tx", label: "up", color: Theme.series.netTx }
      ]
      windowSeconds: 60
      formatValue: function (v) { return Model.formatRate(v) }
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
      emptyText: root.interfaceError !== ""
                 ? "Choose auto or an available interface in Quadrant settings"
                 : (root.ifname === "" ? "No network interface"
                                       : (root.active ? "Sampling…" : "Open this tab to sample"))
      errorText: root.errorText
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Text {
      textFormat: Text.PlainText
      visible: {
        if (!root.ifaceRates) return false
        if (root.ifaceRates.rxBps + root.ifaceRates.txBps < 64) return false
        var rows = root.rows || []
        var i, live = 0, other = 0
        for (i = 0; i < rows.length; i++) {
          if (rows[i].pid === 0) other += Number(rows[i].sortKey) || 0
          else if ((Number(rows[i].sortKey) || 0) > 1) live++
        }
        return live === 0 && other < 64
      }
      text: "Rates include UDP and other users; per-process TCP is empty this interval."
      color: root.panel ? Qt.darker(root.panel.barForeground, 1.5) : "#cacccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
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
