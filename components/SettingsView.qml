import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model

// In-panel settings: every manifest key, written through the store's
// in-process persistence. Device pickers are filled from the identity the
// store already holds. A "Keys" section documents the panel's keyboard.
Column {
  id: root

  property var store: null
  readonly property var cfg: store ? store.cfg : Model.readSettings({})
  readonly property color dim: Model.dimColor(String(Color.foreground), String(Color.background))

  spacing: Style.space(12)

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
    var out = [{ value: "auto", label: "auto (default route)" }]
    var list = store && store.sample && store.sample.net ? store.sample.net : []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].n, label: list[i].n })
    var cur = cfg.networkInterface
    if (cur !== "auto") {
      var seen = false
      for (var j = 0; j < out.length; j++) if (out[j].value === cur) seen = true
      if (!seen) out.push({ value: cur, label: cur + " (not present)" })
    }
    return out
  }
  readonly property var gpuOptions: {
    var out = [{ value: "auto", label: "auto (boot display card)" }]
    var list = store ? store.discreteGpus : []
    for (var i = 0; i < list.length; i++) {
      var g = list[i]
      var info = store && store.sysInfo && store.sysInfo.gpusByCard ? store.sysInfo.gpusByCard[g.card] : null
      out.push({ value: g.card, label: g.card + " · " + (info && info.name ? Model.cleanGpuName(info.name) : g.vendor) })
    }
    if (cfg.gpuDevice !== "auto" && !out.some(function (o) { return o.value === cfg.gpuDevice }))
      out.push({ value: cfg.gpuDevice, label: cfg.gpuDevice + " (not present)" })
    return out
  }
  readonly property var igpuOptions: {
    var out = [{ value: "auto", label: "auto (detect)" }, { value: "none", label: "none (every card is dedicated)" }]
    var list = store ? store.gpus : []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].card, label: list[i].card + " · " + list[i].vendor })
    if (cfg.integratedGpuDevice !== "auto" && cfg.integratedGpuDevice !== "none"
        && !out.some(function (o) { return o.value === cfg.integratedGpuDevice }))
      out.push({ value: cfg.integratedGpuDevice, label: cfg.integratedGpuDevice + " (not present)" })
    return out
  }
  readonly property var diskOptions: {
    var out = [{ value: "auto", label: "auto (disk behind /)" }]
    var list = store && store.diskInfo ? store.diskInfo.disks : []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i].name, label: list[i].name + (list[i].model ? " · " + list[i].model : "") })
    if (cfg.diskDevice !== "auto" && !out.some(function (o) { return o.value === cfg.diskDevice }))
      out.push({ value: cfg.diskDevice, label: cfg.diskDevice + " (not present)" })
    return out
  }

  component Section: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  component SegmentSwitch: Row {
    property string segment: ""
    property string label: ""
    spacing: Style.space(6)
    ToggleSwitch {
      checked: root.cfg.segments.indexOf(parent.segment) !== -1
      anchors.verticalCenter: parent.verticalCenter
      onToggled: root.set("segments", Model.toggleSegment(root.cfg.segments, parent.segment, !checked))
    }
    Text {
      textFormat: Text.PlainText
      text: parent.label
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Section { text: "BAR SEGMENTS" }

  Flow {
    width: parent.width
    spacing: Style.space(14)
    SegmentSwitch { segment: "cpu"; label: "CPU" }
    SegmentSwitch { segment: "gpu"; label: "GPU" }
    SegmentSwitch { segment: "memory"; label: "Memory" }
    SegmentSwitch { segment: "disk"; label: "Drives" }
    SegmentSwitch { segment: "network"; label: "Network" }
  }

  Toggle {
    width: parent.width
    label: "Drives in place of GPU"
    description: "When no dedicated GPU is detected, show the Drives segment where the GPU one would be."
    checked: root.cfg.diskFallbackWithoutGpu
    onClicked: root.set("diskFallbackWithoutGpu", !root.cfg.diskFallbackWithoutGpu)
  }

  Section { text: "APPEARANCE" }

  Flow {
    width: parent.width
    spacing: Style.space(10)
    Dropdown {
      label: "Value colour"
      value: root.cfg.barPalette
      options: [
        { value: "theme", label: "theme · urgent above 90 %" },
        { value: "heat", label: "heat · ramps to urgent" },
        { value: "vivid", label: "vivid · one hue per metric" }
      ]
      onChanged: function (v) { root.set("barPalette", v) }
    }
    Dropdown {
      label: "Labels"
      value: root.cfg.barLabels
      options: [
        { value: "glyph", label: "glyphs" },
        { value: "letter", label: "letters C G M D N" },
        { value: "none", label: "values only" }
      ]
      onChanged: function (v) { root.set("barLabels", v) }
    }
    Dropdown {
      label: "Network rate unit"
      value: root.cfg.rateUnit
      options: [{ value: "bytes", label: "bytes (KiB/s)" }, { value: "bits", label: "bits (Mb/s)" }]
      onChanged: function (v) { root.set("rateUnit", v) }
    }
  }

  Section { text: "SAMPLING" }

  Flow {
    width: parent.width
    spacing: Style.space(10)
    NumberField {
      label: "Process rows"
      value: root.cfg.processCount
      from: 1
      to: 10
      onModified: function (v) { root.set("processCount", v) }
    }
    Dropdown {
      label: "Bar refresh"
      value: String(root.cfg.barIntervalMs)
      options: root.intervalOptions([500, 1000, 2000, 5000, 10000])
      onChanged: function (v) { root.set("barIntervalMs", Number(v)) }
    }
    Dropdown {
      label: "Panel refresh"
      value: String(root.cfg.panelIntervalMs)
      options: root.intervalOptions([1000, 2000, 3000, 5000, 10000])
      onChanged: function (v) { root.set("panelIntervalMs", Number(v)) }
    }
  }

  Section { text: "DEVICES" }

  Flow {
    width: parent.width
    spacing: Style.space(10)
    Dropdown {
      label: "Network interface"
      value: root.cfg.networkInterface
      options: root.interfaceOptions
      onChanged: function (v) { root.set("networkInterface", v) }
    }
    Dropdown {
      label: "Dedicated GPU"
      value: root.cfg.gpuDevice
      options: root.gpuOptions
      onChanged: function (v) { root.set("gpuDevice", v) }
    }
    Dropdown {
      label: "Integrated GPU"
      value: root.cfg.integratedGpuDevice
      options: root.igpuOptions
      onChanged: function (v) { root.set("integratedGpuDevice", v) }
    }
    Dropdown {
      label: "Disk"
      value: root.cfg.diskDevice
      options: root.diskOptions
      onChanged: function (v) { root.set("diskDevice", v) }
    }
  }

  Section { text: "KEYS" }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: "← → or 1–5  switch tab      ↑ ↓  move through processes\nH  last hour / last minute      S  settings      R  re-read hardware      Esc  close\nIn the bar: click a segment for its tab, right-click for btop, scroll to switch tabs."
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    lineHeight: 1.3
  }

  Row {
    spacing: Style.space(8)
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
    Text {
      textFormat: Text.PlainText
      text: "Settings live in ~/.config/omarchy/shell.json and also respond to `omarchy bar set`."
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.parent.width - parent.children[0].width - parent.spacing
      wrapMode: Text.WordWrap
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
