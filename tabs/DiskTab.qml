import QtQuick
import qs.Commons as Commons
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
  property alias processList: processRoster
  property alias actionList: mountControls

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "disk"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var info: model ? model.diskInfo : null
  readonly property var disks: info ? info.disks : []
  readonly property var mounts: info ? info.mounts : []
  readonly property string diskName: model ? model.effectiveDisk : ""
  readonly property var rates: model ? model.diskRates : null
  readonly property var pal: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent), String(Commons.Color.foreground), String(Commons.Color.background))

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
      out.push({ value: d.name, label: d.model ? d.model : d.name, tooltip: (d.deviceId ? d.deviceId + " · " : "") + d.name })
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
  readonly property var rows: Model.formatProcessGroups(model ? model.ioRows : [], "io")
  readonly property var expandedRows: !processRoster.expanded || !root.active ? [] : Model.formatProcessGroups(model ? model.allIoRows : [], "io")
  readonly property string errorText: model ? model.procError : ""


  Column {
    id: column
    width: root.width
    spacing: Commons.Style.space(10)

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
      color: Commons.Color.urgent
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Components.DeviceChoices {
      objectName: "diskChoices"
      width: parent.width
      visible: root.diskOptions.length > 1
      options: root.diskOptions
      value: root.diskName
      fontSize: Commons.Style.font.caption
      onChanged: function (value) { if (root.model) root.model.selectDisk(value) }
    }

    Components.GraphBlock {
      objectName: "diskHistory"
      width: parent.width
      title: "THROUGHPUT"
      finePoints: root.model ? root.model.diskHistory : []
      longPoints: root.model ? root.model.diskLong : []
      longWindow: root.longWindow
      sampleSeconds: root.model ? root.model.barIntervalMs / 1000 : 1
      graphLayout: root.model && root.model.cfg ? root.model.cfg.diskGraphLayout : "overlay"
      minimumMax: 1024
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
      spacing: Commons.Style.space(6)

      Components.SectionHeader { width: parent.width; text: "DEVICE" }
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
      spacing: Commons.Style.space(8)
      visible: root.diskMounts.length > 0

      Components.SectionHeader {
        width: parent.width
        text: "MOUNTS"
      }

      Components.PanelActions {
        id: mountControls
        objectName: "mountActions"
        width: parent.width
        panel: root.panel
        context: root.diskName
        entries: Model.mountActions(root.diskMounts)
        details: Model.mountActionDetails(root.diskMounts)
      }
    }

    PanelSeparator { }

    Components.ProcessList {
      id: processRoster
      panel: root.panel
      active: root.active
      expandable: true
      expandedRows: root.expandedRows
      expandedReady: root.model && root.model.procStats ? root.model.procStats.mode === "expanded" : false
      scopeText: Model.processScope(root.model ? root.model.procStats : null, "io", expanded)
      width: parent.width
      rows: root.rows
      valueHeader: "DISK I/O"
      emptyText: !root.active ? "Open this tab to sample processes"
                 : !root.model || !root.model.procStats ? "Measuring disk I/O rates…"
                 : root.model.procStats.ioVisible === 0 ? "Process I/O visibility is restricted"
                 : root.model.procStats.rateState === "unavailable" ? "Disk I/O rates unavailable without counter state"
                 : !(root.model.procStats.dt > 0) || root.model.procStats.ioReady === 0 ? "Measuring disk I/O rates…"
                 : "No disk activity from visible processes"
      errorText: root.errorText
    }


  }
}
