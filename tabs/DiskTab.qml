import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "../components" as Components

// Drives tab: device identity, 60s read/write history, per-mount capacity.
// Per-process disk I/O is deferred — /proc/<pid>/io is only readable for
// the user's own processes, so a half-attributed list would lie.
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "disk"
  readonly property var info: model ? model.diskInfo : null
  readonly property var disks: info ? info.disks : []
  readonly property var mounts: info ? info.mounts : []
  readonly property string diskName: model ? model.effectiveDisk : ""
  readonly property var rates: model ? model.diskRates : null
  readonly property var selectedDisk: {
    if (!diskName || !disks) return null
    for (var i = 0; i < disks.length; i++)
      if (disks[i].name === diskName) return disks[i]
    return null
  }
  readonly property string diskError: {
    var pin = model ? model.diskDeviceError : ""
    var info = model ? model.diskInfoError : ""
    if (pin && info) return pin + " · " + info
    return pin || info || ""
  }

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (!active) return
    if (model && model.refreshDiskInfo) model.refreshDiskInfo()
  }

  readonly property string diskTitle: {
    var d = selectedDisk
    if (d && d.model) return d.model
    if (diskName) return diskName
    return "Storage"
  }

  readonly property string diskMeta: {
    var d = selectedDisk
    var bits = []
    if (diskName) bits.push(diskName)
    if (d) {
      if (d.rotational === true) bits.push("HDD")
      else if (d.rotational === false) bits.push("SSD")
      if (d.sizeBytes) bits.push(Model.formatBytes(d.sizeBytes))
    }
    return bits.join(" · ")
  }

  readonly property string diskDetail: {
    var d = selectedDisk
    if (d && d.tempC !== null && d.tempC !== undefined) return Model.formatTemp(d.tempC)
    return ""
  }

  readonly property var diskMounts: {
    var list = mounts
    var out = []
    if (!list || list.length === 0 || !diskName) return out
    var backing = info && info.backing ? info.backing : {}
    var i, m
    for (i = 0; i < list.length; i++) {
      m = list[i]
      if (Model.resolveBackingDisk(m.source, backing) === diskName)
        out.push(m)
    }
    return out
  }

  readonly property var primaryMount: {
    var list = diskMounts
    if (!list || list.length === 0) return null
    var i
    for (i = 0; i < list.length; i++) if (list[i].target === "/") return list[i]
    return list[0]
  }

  Timer {
    id: cadence
    interval: root.panel ? root.panel.panelIntervalMs : 2000
    repeat: true
    running: root.active
    onTriggered: root.refresh()
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    Components.HardwareHero {
      width: parent.width
      visible: root.diskName !== "" || root.diskTitle !== "Storage"
      title: root.diskTitle
      meta: root.diskMeta
      detail: root.diskDetail
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Text {
      textFormat: Text.PlainText
      visible: root.diskError !== ""
      text: root.diskError
      color: Color.urgent
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      visible: root.disks.length > 1
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: "Disk"
        color: root.panel ? Qt.darker(root.panel.barForeground, 1.4) : "#cacccc"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Repeater {
        model: root.disks

        delegate: Rectangle {
          required property var modelData
          readonly property bool current: root.diskName === modelData.name
          width: diskLabel.implicitWidth + Style.space(12)
          height: diskLabel.implicitHeight + Style.space(6)
          radius: Style.cornerRadius
          color: current ? Style.selectedFillFor(root.panel ? root.panel.barForeground : "#cacccc", Color.accent)
                         : Style.normalFillFor(root.panel ? root.panel.barForeground : "#cacccc", Color.accent)

          Text {
            id: diskLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.name
            color: root.panel ? root.panel.barForeground : "#cacccc"
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.model) root.model.selectDisk(modelData.name)
          }
        }
      }
    }

    Components.HistoryGraph {
      width: parent.width
      capacity: root.model ? root.model.historyLimit : 60
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      gridColor: Theme.gridFor(root.panel ? root.panel.barForeground : "#cacccc")
      series: [
        { label: "read", color: Theme.series.diskRead, values: (root.model ? root.model.diskHistory : []).map(function (p) { return p.r }) },
        { label: "write", color: Theme.series.diskWrite, values: (root.model ? root.model.diskHistory : []).map(function (p) { return p.w }) }
      ]
    }

    Row {
      spacing: Style.space(10)

      Repeater {
        model: [
          { label: "read", color: Theme.series.diskRead },
          { label: "write", color: Theme.series.diskWrite }
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

    Components.StatRow {
      width: parent.width
      label: "Read / Write"
      value: root.rates
             ? Model.formatRate(root.rates.readBps) + " / " + Model.formatRate(root.rates.writeBps)
             : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      valueBold: true
    }

    Components.StatRow {
      width: parent.width
      label: "Busy"
      value: root.rates ? Model.formatPct(root.rates.utilPct) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "IOPS r/w"
      value: root.rates
             ? String(Math.round(root.rates.readIops)) + " / " + String(Math.round(root.rates.writeIops))
             : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Row {
      width: parent.width
      spacing: ring.visible ? Style.space(18) : 0
      visible: root.primaryMount !== null || root.diskMounts.length > 0

      Components.RingGauge {
        id: ring
        readonly property var m: root.primaryMount
        visible: m !== null
        fraction: m ? Model.clamp(m.pct / 100, 0, 1) : 0
        color: Theme.series.diskRead
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: m ? Model.formatPct(m.pct) : "--"
        subText: m ? m.target : "used"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: mountCol
        width: parent.width - (ring.visible ? ring.width + parent.spacing : 0)
        spacing: Style.space(6)

        Repeater {
          model: root.diskMounts

          delegate: Components.StatRow {
            required property var modelData
            width: mountCol.width
            label: String(modelData.target || "mount")
            value: {
              var used = Model.formatBytes(modelData.used)
              var size = Model.formatBytes(modelData.size)
              var pct = Model.formatPct(modelData.pct)
              return used + " of " + size + " · " + pct
            }
            foreground: root.panel ? root.panel.barForeground : "#cacccc"
            fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: "Per-process disk I/O is not shown: /proc/<pid>/io is only readable for your own processes."
      color: root.panel ? Qt.darker(root.panel.barForeground, 1.6) : "#cacccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
