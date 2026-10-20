import QtQuick
import qs.Commons as Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "../components" as Components

// Memory tab: usable RAM and DIMM identity, grouped readings, a
// used-memory history framed on its own range, the composition bar, swap,
// and the top-by-PSS roster.
Item {
  id: root

  property var panel: null
  property var model: null
  property alias processList: processRoster

  readonly property bool active: panel !== null && panel.opened === true && panel.currentTab === "mem"
  readonly property bool longWindow: panel !== null && panel.longWindow === true
  readonly property var sample: model ? model.sample : null
  readonly property var comp: model ? model.memComp : null
  readonly property var swap: sample ? Model.swapUsage(sample.mem) : null
  readonly property var swapRate: model ? model.swapRate : null
  readonly property var sysMem: model && model.sysInfo ? model.sysInfo.mem : null
  readonly property var psi: sample ? sample.psi : null
  readonly property var pal: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent), String(Commons.Color.foreground), String(Commons.Color.background))

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  onActiveChanged: if (active) refresh()

  function refresh() {
    if (active && model) model.pollProcesses()
  }

  readonly property string memTitle: comp ? Model.formatKiB(comp.totalK) + " usable" : "Memory"
  readonly property string memMeta: sysMem && sysMem.ram && sysMem.ram.label ? sysMem.ram.label : ""

  readonly property var compositionSegments: {
    var c = root.comp
    if (!c || !(c.totalK > 0)) return []
    return [
      { fraction: c.appsK / c.totalK, color: root.pal.primary },
      { fraction: c.cacheK / c.totalK, color: root.pal.secondary },
      { fraction: c.kernelK / c.totalK, color: root.pal.tertiary }
    ]
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

  readonly property var rows: Model.formatProcessGroups(model ? model.memRows : [], "mem")
  readonly property var expandedRows: !processRoster.expanded || !root.active ? [] : Model.formatProcessGroups(model ? model.allMemRows : [], "mem")
  readonly property string errorText: model ? model.procError : ""

  Column {
    id: column
    width: root.width
    spacing: Commons.Style.space(12)

    Components.Hero {
      width: parent.width
      detailsTarget: root
      title: root.memTitle
      meta: root.memMeta
    }

    Components.AdaptiveColumns {
      objectName: "resourceColumns"
      width: parent.width
      primary: [
        Components.SectionCard {
          width: parent.width
          title: "Memory usage"

          Components.MetricReadout {
            width: parent.width
            value: root.comp ? Model.formatKiB(root.comp.usedK) : "--"
            label: "Used"
            hint: root.comp ? Model.formatPct(root.comp.usedPct) + " of " + Model.formatKiB(root.comp.totalK) + " usable" : "Waiting for data"
          }

          Components.GraphBlock {
            width: parent.width
            title: "USED"
            finePoints: root.model ? root.model.memHistory : []
            longPoints: root.model ? root.model.memLong : []
            longWindow: root.longWindow
            sampleSeconds: root.model ? root.model.barIntervalMs / 1000 : 1
            band: true
            fixedMax: 100
            formatValue: function (v) { return Model.formatPct(v, 1) }
            fields: [{ key: "u", label: "used", color: root.pal.primary }]
            legend: [
              { label: "used", color: root.pal.primary, value: root.comp ? Model.formatPct(root.comp.usedPct, 1) : "--" },
              { label: "pressure", color: root.pal.hot, value: root.psi && root.psi.ms10 !== null ? Model.formatPct(root.psi.ms10, 1) + " some" : "--" }
            ]
            onToggleWindow: if (root.panel) root.panel.longWindow = !root.panel.longWindow
          }

          Components.StatRow { width: parent.width; wrapValue: true; label: "Available"; value: root.sample && root.sample.mem ? Model.formatKiB(root.sample.mem.avl) : "--" }

          Components.StatRow { width: parent.width; wrapValue: true; label: "Pressure · some"; value: root.psi && root.psi.ms10 !== null && root.psi.ms10 !== undefined ? Model.formatPct(root.psi.ms10, 1) : "--"; objectName: "memoryPressure" }

          Components.Disclosure {
            width: parent.width
            title: "Memory accounting"
            Text {
              objectName: "memoryAccounting"
              textFormat: Text.PlainText
              text: "Used = total − available. Composition separates free RAM, cache, kernel (unreclaimable slab) and the remaining application estimate."
              color: root.pal.dim
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }
        },
        Components.SectionCard {
          width: parent.width
          title: "RAM composition"

          Components.CompositionBar {
            width: parent.width
            segments: root.compositionSegments
          }
          Repeater {
            model: [
              { label: "Applications", color: root.pal.primary, value: root.comp ? Model.formatKiB(root.comp.appsK) : "--" },
              { label: "Cache", color: root.pal.secondary, value: root.comp ? Model.formatKiB(root.comp.cacheK) : "--" },
              { label: "Kernel", color: root.pal.tertiary, value: root.comp ? Model.formatKiB(root.comp.kernelK) : "--" },
              { label: "Free", color: root.pal.track, value: root.comp ? Model.formatKiB(root.comp.freeK) : "--" }
            ]
            delegate: Item {
              required property var modelData
              width: parent.width
              implicitHeight: legendLabel.implicitHeight
              Rectangle {
                id: swatch
                width: Commons.Style.space(8)
                height: Commons.Style.space(8)
                radius: Commons.Style.space(2)
                color: parent.modelData.color
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: legendLabel
                textFormat: Text.PlainText
                text: parent.modelData.label
                color: root.pal.dim
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                anchors.left: swatch.right
                anchors.leftMargin: Commons.Style.space(5)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: parent.modelData.value
                color: Commons.Color.foreground
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                font.features: ({ "tnum": 1 })
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }
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
            expandable: true
            expandedRows: root.expandedRows
            expandedReady: root.model && root.model.procStats ? root.model.procStats.mode === "expanded" : false
            scopeText: Model.processScope(root.model ? root.model.procStats : null, "mem", expanded)
            width: parent.width
            rows: root.rows
            valueHeader: "SIZE · % RAM"
            emptyText: root.active ? "Measuring memory…" : "Open this tab to sample processes"
            errorText: root.errorText
          }
        },
        Components.SectionCard {
          width: parent.width
          title: "Swap"

          Components.MetricReadout {
            width: parent.width
            value: root.swap ? Model.formatKiB(root.swap.usedK) : "--"
            label: "Used"
            hint: root.swap ? Model.formatKiB(root.swap.totalK) + " total" : "Waiting for data"
          }
          Components.StatRow {
            wrapValue: true
            width: parent.width
            visible: root.swap && root.swap.totalK > 0
            label: "Swap in/out"
            value: root.swapRate ? Model.formatRate(root.swapRate.inKBs * 1024) + " / " + Model.formatRate(root.swapRate.outKBs * 1024) : "--"
          }
          Components.Disclosure {
            objectName: "swapDevices"
            width: parent.width
            visible: root.swapDeviceRows.length > 0
            title: "Swap devices"
            Repeater {
              model: root.swapDeviceRows
              delegate: Components.StatRow {
                wrapValue: true
                required property var modelData
                width: parent.width
                label: modelData.label
                value: modelData.value
              }
            }
          }
        }
      ]
    }
  }
}
