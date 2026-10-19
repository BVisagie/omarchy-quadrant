import QtQuick
import qs.Commons as Commons
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
  readonly property string gpuSelection: cfg.gpuDeviceId || cfg.gpuDevice
  readonly property string igpuSelection: cfg.integratedGpuDeviceId || cfg.integratedGpuDevice
  readonly property string diskSelection: cfg.diskDeviceId || cfg.diskDevice
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))
  readonly property real labelColumn: Math.round(width * 0.40)
  readonly property real controlColumn: Math.max(0, width - labelColumn - Commons.Style.space(10))
  readonly property int switchHeight: Math.max(16, Math.round(Commons.Style.spacing.controlHeight * 0.5))

  spacing: Commons.Style.space(14)

  function set(key, value) {
    if (!store) return
    var patch = {}
    patch[key] = value
    store.persistSettings(patch)
  }

  function segmentChecked(name) {
    if (name === "disk" && store && typeof store.segmentEnabled === "function") return store.segmentEnabled(name)
    return cfg.segments.indexOf(name) >= 0
  }
  function toggleSegment(name, enabled) {
    if (name === "disk" && store && typeof store.setBarSegment === "function") store.setBarSegment(name, enabled)
    else set("segments", Model.toggleSegment(cfg.segments, name, enabled))
  }

  readonly property var segmentLabels: ({ cpu: "CPU", gpu: "GPU", memory: "Memory", disk: "Drives", network: "Network" })
  function moveSegment(name, direction) {
    set("barOrder", Model.moveBarSegment(cfg.barOrder, name, direction))
    Qt.callLater(function () {
      var row = orderRows.itemAt(root.cfg.barOrder.indexOf(name))
      if (row) row.focusMove(direction)
    })
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
      out.push({ value: g.deviceId || g.card, label: g.card + " · " + (Model.gpuDisplayName(g) || g.vendor) })
    }
    if (gpuSelection !== "auto" && !out.some(function (o) { return o.value === root.gpuSelection }))
      out.push({ value: gpuSelection, label: gpuSelection + " · not present" })
    return out
  }
  readonly property var igpuOptions: {
    var out = [{ value: "auto", label: "auto · detect" }, { value: "none", label: "none · every card is dedicated" }]
    var list = store ? store.gpus : []
    for (var i = 0; i < list.length; i++)
      out.push({ value: list[i].deviceId || list[i].card, label: list[i].card + " · " + list[i].vendor })
    if (igpuSelection !== "auto" && igpuSelection !== "none"
        && !out.some(function (o) { return o.value === root.igpuSelection }))
      out.push({ value: igpuSelection, label: igpuSelection + " · not present" })
    return out
  }
  readonly property var diskOptions: {
    var out = [{ value: "auto", label: "auto · disk behind /" }]
    var list = store && store.diskInfo ? store.diskInfo.disks : []
    for (var i = 0; i < list.length; i++)
      out.push({ value: list[i].deviceId || list[i].name, label: list[i].name + (list[i].model ? " · " + list[i].model : "") })
    if (diskSelection !== "auto" && !out.some(function (o) { return o.value === root.diskSelection }))
      out.push({ value: diskSelection, label: diskSelection + " · not present" })
    return out
  }

  // ---- building blocks ---------------------------------------------------
  component Section: Column {
    property string title: ""
    default property alias rows: body.data
    width: root.width
    spacing: Commons.Style.space(8)
    Text {
      textFormat: Text.PlainText
      text: parent.title
      color: root.dim
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
    }
    Column { id: body; width: parent.width; spacing: Commons.Style.space(6) }
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
      spacing: Commons.Style.space(2)
      Text {
        textFormat: Text.PlainText
        text: parent.parent.label
        color: Commons.Color.foreground
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        width: parent.width
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: parent.parent.hint
        color: root.dim
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
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
    fontFamily: Commons.Style.font.family
  }

  // Enabled membership and saved order stay independent of device presence.
  Section {
    title: "BAR SEGMENTS"
    Repeater {
      id: orderRows
      model: root.cfg.barOrder
      delegate: Item {
        id: segmentRow
        required property string modelData
        required property int index
        width: root.width
        implicitHeight: Math.max(moveButtons.implicitHeight, segmentSwitch.implicitHeight)
        function focusMove(direction) {
          var target = direction < 0 ? earlierButton : laterButton
          if (!target.enabled) target = direction < 0 ? laterButton : earlierButton
          target.forceActiveFocus()
        }
        ToggleSwitch {
          id: segmentSwitch
          objectName: "segmentSwitch_" + segmentRow.modelData
          checked: root.segmentChecked(segmentRow.modelData)
          cursorRing: false
          trackHeight: root.switchHeight
          anchors.verticalCenter: parent.verticalCenter
          Accessible.name: "Show " + root.segmentLabels[segmentRow.modelData] + " in bar"
          onToggled: root.toggleSegment(segmentRow.modelData, !checked)
        }
        Text {
          textFormat: Text.PlainText
          text: (segmentRow.index + 1) + " · " + root.segmentLabels[segmentRow.modelData]
          color: Commons.Color.foreground
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.body
          anchors.left: segmentSwitch.right
          anchors.leftMargin: Commons.Style.space(6)
          anchors.right: moveButtons.left
          anchors.rightMargin: Commons.Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
        }
        Row {
          id: moveButtons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(4)
          Button {
            id: earlierButton
            objectName: "moveEarlier_" + segmentRow.modelData
            text: "↑"
            enabled: segmentRow.index > 0
            opacity: enabled ? 1 : 0.35
            focusable: true
            bordered: true
            fontSize: Commons.Style.font.caption
            tooltipText: "Move " + root.segmentLabels[segmentRow.modelData] + " earlier"
            Accessible.name: tooltipText
            onClicked: root.moveSegment(segmentRow.modelData, -1)
          }
          Button {
            id: laterButton
            objectName: "moveLater_" + segmentRow.modelData
            text: "↓"
            enabled: segmentRow.index < root.cfg.barOrder.length - 1
            opacity: enabled ? 1 : 0.35
            focusable: true
            bordered: true
            fontSize: Commons.Style.font.caption
            tooltipText: "Move " + root.segmentLabels[segmentRow.modelData] + " later"
            Accessible.name: tooltipText
            onClicked: root.moveSegment(segmentRow.modelData, 1)
          }
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Missing or disabled devices keep their saved positions."
      color: root.dim
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }
    FormRow {
      label: "Drives fallback"
      hint: "When GPU is unavailable, show Drives at its saved position."
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
      label: "Bar style"
      Pick {
        objectName: "barStyleChoice"
        value: root.cfg.barStyle
        options: [{ value: "text", label: "text" }, { value: "graph-text", label: "graph + text" }]
        onChanged: function (v) { root.set("barStyle", v) }
      }
    }
    FormRow {
      visible: root.cfg.barStyle === "graph-text"
      label: "Trend width"
      hint: "16–64 px; vertical bars fit the strip."
      NumberField {
        objectName: "barGraphWidthChoice"
        width: root.controlColumn
        fieldWidth: root.controlColumn
        value: root.cfg.barGraphWidth
        from: 16
        to: 64
        fontFamily: Commons.Style.font.family
        onModified: function (v) { root.set("barGraphWidth", v) }
      }
    }
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

  Section {
    title: "PANEL GRAPHS"
    FormRow {
      label: "GPU"
      hint: "Aligned plots share the 0–100 % scale."
      Pick {
        objectName: "gpuGraphLayoutChoice"
        value: root.cfg.gpuGraphLayout
        options: [{ value: "overlay", label: "overlay" }, { value: "aligned", label: "aligned · busy / VRAM" }]
        onChanged: function (v) { root.set("gpuGraphLayout", v) }
      }
    }
    FormRow {
      label: "Network"
      hint: "Mirrored: down above zero, up below."
      Pick {
        objectName: "networkGraphLayoutChoice"
        value: root.cfg.networkGraphLayout
        options: [{ value: "overlay", label: "overlay" }, { value: "mirrored", label: "mirrored · down / up" }]
        onChanged: function (v) { root.set("networkGraphLayout", v) }
      }
    }
    FormRow {
      label: "Drives"
      hint: "Mirrored: read above zero, write below."
      Pick {
        objectName: "diskGraphLayoutChoice"
        value: root.cfg.diskGraphLayout
        options: [{ value: "overlay", label: "overlay" }, { value: "mirrored", label: "mirrored · read / write" }]
        onChanged: function (v) { root.set("diskGraphLayout", v) }
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
        fontFamily: Commons.Style.font.family
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
      hint: root.cfg.gpuDevice !== "auto" && !root.cfg.gpuDeviceId ? "Pin uses a kernel name; no unique PCI address." : ""
      Pick { value: root.gpuSelection; options: root.gpuOptions; onChanged: function (v) { if (root.store) root.store.selectGpu(v) } }
    }
    FormRow {
      label: "Integrated GPU"
      hint: root.cfg.integratedGpuDevice !== "auto" && root.cfg.integratedGpuDevice !== "none" && !root.cfg.integratedGpuDeviceId ? "Pin uses a kernel name; no unique PCI address." : ""
      Pick { value: root.igpuSelection; options: root.igpuOptions; onChanged: function (v) { if (root.store) root.store.selectIntegratedGpu(v) } }
    }
    FormRow {
      label: "Disk"
      hint: root.cfg.diskDevice !== "auto" && !root.cfg.diskDeviceId ? "Pin uses a kernel name; no unique disk ID." : ""
      Pick { value: root.diskSelection; options: root.diskOptions; onChanged: function (v) { if (root.store) root.store.selectDisk(v) } }
    }
  }

  // ---- keys --------------------------------------------------------------
  Section {
    title: "KEYS"
    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Commons.Style.space(14)
      rowSpacing: Commons.Style.space(3)
      Repeater {
        model: [
          "← →  or  1–" + (root.store && root.store.discreteGpuAvailable ? 5 : 4), "switch tab",
          "↑ ↓", "process rows or selected actions",
          "H", "last hour / last minute on every graph",
          "S", "settings",
          "R", "re-read hardware identity",
          "/", "search processes (CPU, Memory, Drives)",
          "A", "copy/open actions (Network, Drives)",
          "Esc", "leave actions/search, close view",
          "Tab", "next bar panel (the shell's own binding)"
        ]
        delegate: Text {
          required property string modelData
          required property int index
          textFormat: Text.PlainText
          text: modelData
          width: index % 2 === 0 ? Commons.Style.space(110) : parent.width - Commons.Style.space(110) - Commons.Style.space(14)
          color: index % 2 === 0 ? Commons.Color.foreground : root.dim
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
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
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }
  }

  // ---- footer ------------------------------------------------------------
  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Settings are stored on this widget's entry in ~/.config/omarchy/shell.json and also follow `omarchy bar set`."
      color: root.dim
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }
    Button {
      objectName: "resetSettings"
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
