import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "../components" as Components

// Drives tab: device identity, disk picker, read/write history, rates,
// per-mount capacity with usage bars, and the I/O roster for the
// processes you own (the kernel hides /proc/<pid>/io for everyone else,
// and the list says how many it could not read).
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "disk"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var info: model ? model.diskInfo : null
  readonly property var disks: info ? info.disks : []
  readonly property var mounts: info ? info.mounts : []
  readonly property string diskName: model ? model.effectiveDisk : ""
  readonly property var rates: model ? model.diskRates : null
  readonly property var pal: Model.seriesPalette(String(Color.accent), String(Color.urgent), String(Color.foreground), String(Color.background))

  readonly property var selectedDisk: {
    if (!diskName || !disks) return null
    for (var i = 0; i < disks.length; i++)
      if (disks[i].name === diskName) return disks[i]
    return null
  }
  readonly property string diskError: {
    var pin = model ? model.diskDeviceError : ""
    var err = model ? model.diskInfoError : ""
    if (pin && err) return pin + " · " + err
    return pin || err || ""
  }

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (!active || !model) return
    model.pollDiskUsage()
    model.pollProcesses()
  }

  // ---- identity ----------------------------------------------------------
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
  readonly property var diskOptions: {
    var out = []
    for (var i = 0; i < disks.length; i++) {
      var d = disks[i]
      out.push({ value: d.name, label: d.model ? d.model : d.name, tooltip: d.name })
    }
    return out
  }
  readonly property var diskMounts: {
    var list = mounts
    var out = []
    if (!list || list.length === 0 || !diskName) return out
    var backing = info && info.backing ? info.backing : {}
    for (var i = 0; i < list.length; i++) {
      if (Model.resolveBackingDisk(list[i].source, backing) === diskName) out.push(list[i])
    }
    return out
  }

  // ---- rows --------------------------------------------------------------
  readonly property var rows: {
    var src = model ? model.ioRows : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      out.push({ pid: src[i].pid, comm: src[i].comm, history: src[i].history, sortKey: src[i].sortKey,
                 valueText: "R " + Model.formatRate(src[i].read) + "  W " + Model.formatRate(src[i].write) })
    }
    return out
  }
  readonly property string errorText: model ? model.procError : ""
  readonly property string ioNote: {
    var s = model ? model.procStats : null
    if (!s) return ""
    if (s.ioHidden === 0) return ""
    return "I/O of " + s.ioHidden + " processes owned by other users is not visible."
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(10)

    Components.Hero {
      width: parent.width
      title: root.diskTitle
      meta: root.diskMeta
      detail: root.diskDetail
    }

    Text {
      textFormat: Text.PlainText
      visible: root.diskError !== ""
      text: root.diskError
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    ButtonGroup {
      visible: root.diskOptions.length > 1
      options: root.diskOptions
      value: root.diskName
      fontSize: Style.font.caption
      onChanged: function (value) { if (root.model) root.model.selectDisk(value) }
    }

    Components.GraphBlock {
      width: parent.width
      title: "THROUGHPUT"
      finePoints: root.model ? root.model.diskHistory : []
      longPoints: root.model ? root.model.diskLong : []
      longWindow: root.longWindow
      sampleSeconds: root.model ? root.model.barIntervalMs / 1000 : 1
      formatValue: function (v) { return Model.formatRate(v) }
      fields: [
        { key: "r", label: "read", color: root.pal.primary },
        { key: "w", label: "write", color: root.pal.secondary }
      ]
      legend: [
        { label: "read", color: root.pal.primary, value: root.rates ? Model.formatRate(root.rates.readBps) : "--" },
        { label: "write", color: root.pal.secondary, value: root.rates ? Model.formatRate(root.rates.writeBps) : "--" }
      ]
      onToggleWindow: if (root.panel) root.panel.longWindow = !root.panel.longWindow
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Components.StatRow {
        width: parent.width
        label: "Busy"
        value: root.rates ? Model.formatPct(root.rates.utilPct) : "--"
      }
      Components.StatRow {
        width: parent.width
        label: "IOPS r/w"
        value: root.rates ? String(Math.round(root.rates.readIops)) + " / " + String(Math.round(root.rates.writeIops)) : "--"
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.diskMounts.length > 0

      Components.SectionHeader {
        width: parent.width
        text: "MOUNTS"
      }

      Repeater {
        model: root.diskMounts

        delegate: Column {
          id: mountRow
          required property var modelData
          readonly property real pct: Math.max(0, Math.min(100, Number(modelData.pct) || 0))
          width: parent.width
          spacing: Style.space(3)

          Components.StatRow {
            width: parent.width
            label: String(mountRow.modelData.target || "mount")
            value: Model.formatBytes(mountRow.modelData.used) + " of " + Model.formatBytes(mountRow.modelData.size)
                   + " · " + Model.formatPct(mountRow.pct)
            labelColor: Color.foreground
            valueColor: root.pal.dim
            labelMaximumRatio: 0.5
          }
          Components.CompositionBar {
            width: parent.width
            barHeight: Style.space(4)
            segments: [{ fraction: mountRow.pct / 100, color: Model.heatColor(mountRow.pct, root.pal.primary, root.pal.primary, root.pal.hot, 80) }]
          }
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
      valueHeader: "DISK I/O"
      emptyText: root.active ? "No disk activity from your processes" : "Open this tab to sample processes"
      errorText: root.errorText
    }

    Text {
      textFormat: Text.PlainText
      visible: root.ioNote !== ""
      text: root.ioNote
      color: root.pal.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }
}
