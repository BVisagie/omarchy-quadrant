import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model

// In-panel settings: a two-column form — label on the left, control on the
// right, every control the same width — written through the store's
// in-process persistence. Device pickers are filled from the identity the
// store already holds. A Keys table documents the panel's keyboard.
Column {
  id: root

  property var store: null
  readonly property var cfg: store ? store.cfg : Model.readSettings({})
  readonly property color dim: Model.dimColor(String(Color.foreground), String(Color.background))
  readonly property real labelColumn: Math.round(width * 0.40)
  readonly property real controlColumn: Math.max(0, width - labelColumn - Style.space(10))
  readonly property int switchHeight: Math.max(16, Math.round(Style.spacing.controlHeight * 0.5))

  spacing: Style.space(14)

  function set(key, value) {
    if (!store) return
    var patch = {}
    patch[key] = value
    store.persistSettings(patch)
  }

  function intervalOptions(list) {
    var out = []
    for (var i = 0; i < list.length; i++)
      out.push({ value: String(list[i]), label: list[i] >= 1000 ? (list[i] / 1000) + " s" : list[i] + " ms" })
    return out
  }

  readonly property var interfaceOptions: {
    var out = [{ value: "auto", label: "auto · default route" }]
    var list = store && store.sample && store.sample.net ? store.sample.net : []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].n, label: list[i].n })
    var cur = cfg.networkInterface
    if (cur !== "auto" && !out.some(function (o) { return o.value === cur }))
      out.push({ value: cur, label: cur + " · not present" })
    return out
  }
  readonly property var gpuOptions: {
    var out = [{ value: "auto", label: "auto · boot display card" }]
    var list = store ? store.discreteGpus : []
    for (var i = 0; i < list.length; i++) {
      var g = list[i]
      var info = store && store.sysInfo && store.sysInfo.gpusByCard ? store.sysInfo.gpusByCard[g.card] : null
      out.push({ value: g.card, label: g.card + " · " + (info && info.name ? Model.cleanGpuName(info.name) : g.vendor) })
    }
    if (cfg.gpuDevice !== "auto" && !out.some(function (o) { return o.value === cfg.gpuDevice }))
      out.push({ value: cfg.gpuDevice, label: cfg.gpuDevice + " · not present" })
    return out
  }
  readonly property var igpuOptions: {
    var out = [{ value: "auto", label: "auto · detect" }, { value: "none", label: "none · every card is dedicated" }]
    var list = store ? store.gpus : []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].card, label: list[i].card + " · " + list[i].vendor })
    if (cfg.integratedGpuDevice !== "auto" && cfg.integratedGpuDevice !== "none"
        && !out.some(function (o) { return o.value === cfg.integratedGpuDevice }))
      out.push({ value: cfg.integratedGpuDevice, label: cfg.integratedGpuDevice + " · not present" })
    return out
  }
  readonly property var diskOptions: {
    var out = [{ value: "auto", label: "auto · disk behind /" }]
    var list = store && store.diskInfo ? store.diskInfo.disks : []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].name, label: list[i].name + (list[i].model ? " · " + list[i].model : "") })
    if (cfg.diskDevice !== "auto" && !out.some(function (o) { return o.value === cfg.diskDevice }))
      out.push({ value: cfg.diskDevice, label: cfg.diskDevice + " · not present" })
    return out
  }

  // ---- building blocks ---------------------------------------------------
  component Section: Column {
    property string title: ""
    default property alias rows: body.data
    width: root.width
    spacing: Style.space(8)
    Text {
      textFormat: Text.PlainText
      text: parent.title
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Column { id: body; width: parent.width; spacing: Style.space(6) }
  }

  // Label column + control column, control vertically centred on the label.
  component FormRow: Item {
    property string label: ""
    property string hint: ""
    default property alias control: slot.data
    width: root.width
    implicitHeight: Math.max(labelCol.implicitHeight, slot.childrenRect.height)
    Column {
      id: labelCol
      width: root.labelColumn
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        textFormat: Text.PlainText
        text: parent.parent.label
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        width: parent.width
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: parent.parent.hint
        color: root.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        width: parent.width
        wrapMode: Text.WordWrap
      }
    }
    Item {
      id: slot
      width: root.controlColumn
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: childrenRect.height
    }
  }

  component Pick: Dropdown {
    width: root.controlColumn
    showLabel: false
    fontFamily: Style.font.family
  }

  // ---- bar segments: five compact switches on one line ------------------
  Section {
    title: "BAR SEGMENTS"

    Grid {
      width: parent.width
      columns: 5
      rowSpacing: Style.space(6)

      Repeater {
        model: [
          { key: "cpu", label: "CPU" }, { key: "gpu", label: "GPU" }, { key: "memory", label: "Memory" },
          { key: "disk", label: "Drives" }, { key: "network", label: "Network" }
        ]
        delegate: Row {
          required property var modelData
          width: Math.floor(root.width / 5)
          spacing: Style.space(6)
          ToggleSwitch {
            checked: root.cfg.segments.indexOf(parent.modelData.key) !== -1
            cursorRing: false
            trackHeight: root.switchHeight
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.set("segments", Model.toggleSegment(root.cfg.segments, parent.modelData.key, !checked))
          }
          Text {
            textFormat: Text.PlainText
            text: parent.modelData.label
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    FormRow {
      label: "Drives in place of GPU"
      hint: "When no dedicated card is detected, the GPU segment shows Drives."
      ToggleSwitch {
        checked: root.cfg.diskFallbackWithoutGpu
        cursorRing: false
        trackHeight: root.switchHeight
        anchors.right: parent.right
        onToggled: root.set("diskFallbackWithoutGpu", !root.cfg.diskFallbackWithoutGpu)
      }
    }
  }

  // ---- appearance --------------------------------------------------------
  Section {
    title: "APPEARANCE"
    FormRow {
      label: "Value colour"
      Pick {
        value: root.cfg.barPalette
        options: [
          { value: "theme", label: "theme · urgent above 90 %" },
          { value: "heat", label: "heat · ramps to urgent" },
          { value: "vivid", label: "vivid · one hue per metric" }
        ]
        onChanged: function (v) { root.set("barPalette", v) }
      }
    }
    FormRow {
      label: "Labels"
      Pick {
        value: root.cfg.barLabels
        options: [
          { value: "glyph", label: "glyphs" },
          { value: "letter", label: "letters · C G M D N" },
          { value: "none", label: "values only" }
        ]
        onChanged: function (v) { root.set("barLabels", v) }
      }
    }
    FormRow {
      label: "Network rate unit"
      Pick {
        value: root.cfg.rateUnit
        options: [{ value: "bytes", label: "bytes · KiB/s" }, { value: "bits", label: "bits · Mb/s" }]
        onChanged: function (v) { root.set("rateUnit", v) }
      }
    }
  }

  // ---- sampling ----------------------------------------------------------
  Section {
    title: "SAMPLING"
    FormRow {
      label: "Process rows"
      NumberField {
        width: root.controlColumn
        fieldWidth: root.controlColumn
        value: root.cfg.processCount
        from: 1
        to: 10
        fontFamily: Style.font.family
        onModified: function (v) { root.set("processCount", v) }
      }
    }
    FormRow {
      label: "Bar refresh"
      hint: "Stream cadence for the bar and the graphs."
      Pick {
        value: String(root.cfg.barIntervalMs)
        options: root.intervalOptions([500, 1000, 2000, 5000, 10000])
        onChanged: function (v) { root.set("barIntervalMs", Number(v)) }
      }
    }
    FormRow {
      label: "Panel refresh"
      hint: "Process and GPU samplers while the panel is open."
      Pick {
        value: String(root.cfg.panelIntervalMs)
        options: root.intervalOptions([1000, 2000, 3000, 5000, 10000])
        onChanged: function (v) { root.set("panelIntervalMs", Number(v)) }
      }
    }
  }

  // ---- devices -----------------------------------------------------------
  Section {
    title: "DEVICES"
    FormRow {
      label: "Network interface"
      Pick { value: root.cfg.networkInterface; options: root.interfaceOptions; onChanged: function (v) { root.set("networkInterface", v) } }
    }
    FormRow {
      label: "Dedicated GPU"
      Pick { value: root.cfg.gpuDevice; options: root.gpuOptions; onChanged: function (v) { root.set("gpuDevice", v) } }
    }
    FormRow {
      label: "Integrated GPU"
      Pick { value: root.cfg.integratedGpuDevice; options: root.igpuOptions; onChanged: function (v) { root.set("integratedGpuDevice", v) } }
    }
    FormRow {
      label: "Disk"
      Pick { value: root.cfg.diskDevice; options: root.diskOptions; onChanged: function (v) { root.set("diskDevice", v) } }
    }
  }

  // ---- keys --------------------------------------------------------------
  Section {
    title: "KEYS"
    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.space(14)
      rowSpacing: Style.space(3)
      Repeater {
        model: [
          "← →  or  1–5", "switch tab",
          "↑ ↓", "move through the process rows",
          "H", "last hour / last minute on every graph",
          "S", "settings",
          "R", "re-read hardware identity",
          "Esc", "close settings, then the panel",
          "Tab", "next bar panel (the shell's own binding)"
        ]
        delegate: Text {
          required property string modelData
          required property int index
          textFormat: Text.PlainText
          text: modelData
          width: index % 2 === 0 ? Style.space(110) : parent.width - Style.space(110) - Style.space(14)
          color: index % 2 === 0 ? Color.foreground : root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.features: ({ "tnum": 1 })
          wrapMode: Text.WordWrap
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: "In the bar: click a segment for its tab, right-click for btop, scroll to switch tabs while the panel is open."
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // ---- footer ------------------------------------------------------------
  Column {
    width: parent.width
    spacing: Style.space(8)
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Settings are stored on this widget's entry in ~/.config/omarchy/shell.json and also follow `omarchy bar set`."
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Button {
      text: "Reset to defaults"
      onClicked: {
        if (!root.store) return
        var d = Model.SETTING_DEFAULTS
        var patch = {}
        for (var k in d) patch[k] = d[k]
        root.store.persistSettings(patch)
      }
    }
  }
}
