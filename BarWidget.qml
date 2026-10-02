import QtQuick
import qs.Ui
import qs.Commons
import "lib/index.mjs" as Model
import "components" as Components

// Quadrant bar slot: one compact widget covering CPU, GPU, memory, network,
// and an optional disk segment. All sampling and state live in the Store,
// which the shell runs once as the plugin's service; this widget — one copy
// per monitor — binds to it, pushes its settings and viewer state, and
// renders. An empty segments list collapses the slot to a system-monitor
// glyph; the panel stays complete.
BarWidget {
  id: root
  moduleName: "dev.bvisagie.quadrant"

  // ---- store resolution ------------------------------------------------
  // bar.shell.serviceFor() is not a notifying binding, so it is retried a
  // few times after the bar arrives; a shell without services (pre-4.0.3)
  // gets an embedded copy instead.
  property var store: null
  property int storeTries: 0

  function resolveStore() {
    if (root.store) return
    var svc = null
    try {
      if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
        svc = root.bar.shell.serviceFor(root.moduleName)
    } catch (e) {
      svc = null
    }
    if (svc) {
      root.store = svc
      return
    }
    root.storeTries++
    if (root.storeTries >= 10) {
      localStore.active = true
      root.store = localStore.item
      return
    }
    storeRetry.restart()
  }

  Timer {
    id: storeRetry
    interval: 300
    repeat: false
    onTriggered: root.resolveStore()
  }

  Loader {
    id: localStore
    active: false
    sourceComponent: Components.Store {
      embedded: true
      shell: root.bar ? root.bar.shell : null
      runCommand: function (cmd) { if (root.bar && typeof root.bar.run === "function") root.bar.run(cmd) }
    }
  }

  onBarChanged: {
    resolveStore()
    injectPanel()
  }
  onStoreChanged: {
    pushSettings()
    pushViewer()
    injectPanel()
  }
  Component.onCompleted: resolveStore()
  Component.onDestruction: {
    if (store) store.clearViewer(viewerId)
    unregisterCells()
  }

  // ---- settings + viewer state → store ---------------------------------
  function pushSettings() {
    if (root.store) root.store.applySettings(root.settings)
  }
  onSettingsChanged: {
    pushSettings()
    injectPanel()
  }

  readonly property string viewerId: String(root)
  readonly property var viewerState: ({
    gpuSegment: segmentEnabled("gpu") && discreteGpuAvailable,
    gpuTab: panelOpenOn("gpu"),
    cpuTab: panelOpenOn("cpu"),
    memTab: panelOpenOn("mem"),
    diskTab: panelOpenOn("disk"),
    netTab: panelOpenOn("net"),
    open: opened
  })
  onViewerStateChanged: pushViewer()
  function pushViewer() {
    if (root.store) root.store.setViewer(viewerId, viewerState)
  }
  function panelOpenOn(tab) {
    var p = panelLoader.item
    return p ? (p.opened === true && p.currentTab === tab) : false
  }

  // ---- store reads used by the slot ------------------------------------
  readonly property var cpuPct: store ? store.cpuPct : null
  readonly property var memComp: store ? store.memComp : null
  readonly property var diskRates: store ? store.diskRates : null
  readonly property var ifaceRates: store ? store.ifaceRates : null
  readonly property var gpuDisplay: store ? store.gpuDisplay : null
  readonly property var gpu: store ? store.gpu : null
  readonly property bool streamLive: store ? store.streamLive : false
  readonly property bool discreteGpuAvailable: store ? store.discreteGpuAvailable : false
  readonly property bool diskAvailable: store ? store.diskAvailable : false
  readonly property var visibleBarCells: store ? store.visibleBarCells : []
  readonly property string barPaletteMode: store ? store.barPaletteMode : "theme"
  readonly property string barLabelsMode: store ? store.barLabelsMode : "glyph"
  readonly property string rateUnit: store ? store.rateUnit : "bytes"
  function segmentEnabled(name) {
    return store ? store.segmentEnabled(name) : false
  }

  readonly property int visibleSegmentCount: visibleBarCells.length
  readonly property bool showMonitorFallback: visibleSegmentCount === 0
  // Bar glyphs are icons, not captions: they size with the shell's body
  // text so they read at the same weight as neighbouring bar widgets,
  // while the value stays at caption.
  readonly property int glyphFontSize: Style.font.body

  // ---- colours ---------------------------------------------------------
  readonly property color barFg: root.bar ? (root.bar.barForeground || root.bar.foreground) : Color.foreground
  readonly property color barBg: root.bar ? root.bar.background : Color.background
  readonly property color barUrgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color mutedLabelColor: Model.dimColor(String(barFg), String(barBg), 0.38)
  readonly property color quietValueColor: Model.dimColor(String(barFg), String(barBg), 0.12)

  // Hot state with hysteresis: a value enters the hot band at 90 % and only
  // leaves it below 80 %, so a reading hovering on the line cannot flicker.
  property bool cpuHot: false
  property bool memHot: false
  property bool gpuHot: false
  property bool diskHot: false
  onCpuPctChanged: cpuHot = Model.band(cpuHot, cpuPct ? cpuPct.nonIdle : null, 90, 80)
  onMemCompChanged: memHot = Model.band(memHot, memComp ? memComp.usedPct : null, 90, 80)
  onGpuDisplayChanged: gpuHot = Model.band(gpuHot, gpuDisplay ? gpuDisplay.pct : null, 90, 80)
  onDiskRatesChanged: diskHot = Model.band(diskHot, diskRates ? diskRates.utilPct : null, 90, 80)

  // Value colour per palette mode:
  //   theme  foreground, urgent while hot
  //   heat   continuous muted → accent → urgent ramp
  //   vivid  fixed per-resource hue, urgent while hot
  function valueColorFor(metric, pct, hot) {
    if (barPaletteMode === "heat")
      return Model.heatColor(pct === null ? 0 : pct, String(quietValueColor), String(Color.accent), String(barUrgent), 8)
    if (hot) return barUrgent
    if (barPaletteMode === "vivid") return Model.VIVID[metric] || barFg
    return barFg
  }

  readonly property string cpuValueText: cpuPct ? Model.formatPct(cpuPct.nonIdle) : "--"
  readonly property string memValueText: memComp ? Model.formatPct(memComp.usedPct) : "--"
  readonly property string gpuValueText: {
    if (!gpuDisplay) return "--"
    return (gpuDisplay.estimated ? "~" : "") + Model.formatPct(gpuDisplay.pct)
  }
  readonly property string diskValueText: diskRates ? Model.formatPct(diskRates.utilPct) : "--"
  readonly property string netUpText: ifaceRates ? Model.formatRateCompact(ifaceRates.txBps) : "--"
  readonly property string netDownText: ifaceRates ? Model.formatRateCompact(ifaceRates.rxBps) : "--"

  // ---- per-segment tooltips ----------------------------------------------
  function tooltipFor(metric) {
    if (!streamLive) return "Quadrant: sampler offline"
    if (metric === "cpu") return Model.cpuBarTooltip(cpuPct)
    if (metric === "gpu") return gpuDisplay ? "GPU " + Model.formatPct(gpuDisplay.pct) + (gpuDisplay.estimated ? " (frequency estimate)" : "") : "GPU --"
    if (metric === "mem") return memComp ? "Memory " + Model.formatPct(memComp.usedPct) + " used · " + Model.formatKiB(memComp.usedK) : "Memory --"
    if (metric === "disk") return diskRates
      ? "Drives " + Model.formatPct(diskRates.utilPct) + " busy · R " + Model.formatRate(diskRates.readBps) + " · W " + Model.formatRate(diskRates.writeBps)
      : "Drives --"
    if (metric === "net") return ifaceRates
      ? "Network ↓ " + Model.formatRateUnit(ifaceRates.rxBps, rateUnit) + " · ↑ " + Model.formatRateUnit(ifaceRates.txBps, rateUnit)
      : "Network --"
    return "Quadrant"
  }

  readonly property string slotTooltip: {
    if (!streamLive) return "Quadrant: sampler offline"
    if (!showMonitorFallback) return ""
    return "Quadrant"
  }

  // ---- sizing ----------------------------------------------------------
  // Cell width is locked to glyph + "100%" so digits never resize the
  // slot; "~" is reserved only when an Intel GPU can show it.
  readonly property real labelGap: Style.space(3)
  readonly property real segmentGap: Style.space(6)
  readonly property real outerPad: Style.spaceReal(6)

  TextMetrics { id: pctMetrics; font.family: button.fontFamily; font.pixelSize: Style.font.caption; text: "100%" }
  TextMetrics { id: tildeMetrics; font.family: button.fontFamily; font.pixelSize: Style.font.caption; text: "~" }
  TextMetrics { id: netMetrics; font.family: button.fontFamily; font.pixelSize: Style.font.caption; text: root.vertical ? "↓999T" : "↑ 999T  ↓ 999T" }
  TextMetrics { id: glyphMetrics; font.family: button.fontFamily; font.pixelSize: root.glyphFontSize; text: "" }

  function labelFor(metric) {
    return root.vertical ? "" : Model.barLabelFor(root.barLabelsMode, metric)
  }
  function labelWidthFor(metric) {
    var label = labelFor(metric)
    if (label === "") return 0
    glyphMetrics.text = label
    return Math.ceil(glyphMetrics.advanceWidth)
  }
  readonly property int lineBoxHeight: Math.ceil(Math.max(pctMetrics.height, root.vertical ? 0 : glyphMetrics.height))
  readonly property bool reserveEstimatePrefix: {
    if (!root.segmentEnabled("gpu") || !root.discreteGpuAvailable) return false
    return root.gpu && root.gpu.vendor === "intel"
  }
  function metricCellWidthFor(metric) {
    var w = Math.ceil(pctMetrics.advanceWidth)
    if (metric === "gpu" && root.reserveEstimatePrefix) w += Math.ceil(tildeMetrics.advanceWidth)
    var lw = labelWidthFor(metric)
    if (lw > 0) w += labelGap + lw
    if (root.vertical && root.bar) return Math.min(w, root.bar.barSize)
    return w
  }
  readonly property real networkRateWidth: Math.ceil(netMetrics.advanceWidth) + 1
  readonly property real networkCellWidth: {
    var w = root.networkRateWidth
    var lw = labelWidthFor("net")
    if (lw > 0) w += labelGap + lw
    if (root.vertical) return Math.min(w, root.verticalSlot)
    return w
  }
  readonly property int verticalSlot: root.bar ? root.bar.barSize : Style.bar.sizeVertical

  // ---- panel contract (Quattro bar-widget shape) -----------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // A segment click opens the panel on that tab (or closes it when that tab
  // is already showing); a click elsewhere in the slot toggles the panel on
  // the last-used tab. Right-click opens btop, middle-click toggles.
  function segmentClicked(tab) {
    var p = panelLoader.item
    if (!p) return
    if (p.opened) {
      if (p.currentTab === tab) p.close()
      else p.currentTab = tab
    } else {
      p.showTab(tab)
    }
  }

  function launchBtop() {
    Util.execArgv(["omarchy-launch-or-focus-tui", "btop"])
  }

  property real wheelAccumulator: 0
  function handleWheel(delta) {
    var r = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = r.remainder
    var p = panelLoader.item
    if (!p || !p.opened || r.steps === 0) return
    p.stepTab(r.steps > 0 ? -1 : 1)
  }

  // Segment cells are registered as click targets after the slot button
  // so they sit above it in the bar's hit test (the bar walks targets
  // newest first).
  function registerCells() {
    if (!root.bar || typeof root.bar.registerClickTarget !== "function") return
    var cells = [cpuCell, gpuCell, memCell, diskCell, netCell]
    for (var i = 0; i < cells.length; i++) {
      if (typeof root.bar.unregisterClickTarget === "function") root.bar.unregisterClickTarget(cells[i])
      root.bar.registerClickTarget(cells[i])
    }
  }
  function unregisterCells() {
    if (!root.bar || typeof root.bar.unregisterClickTarget !== "function") return
    var cells = [cpuCell, gpuCell, memCell, diskCell, netCell]
    for (var i = 0; i < cells.length; i++) root.bar.unregisterClickTarget(cells[i])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property real indicatorSlot: showMonitorFallback ? Style.bar.statusSlot : Style.bar.iconSlot
  readonly property real openPanelIndicatorWidth: Math.max(Style.space(10), Math.round(indicatorSlot * 0.55))
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(indicatorSlot * 0.55))

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- bar slot ----------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showMonitorFallback ? Model.BAR_GLYPHS.monitor : ""
    hasVisualContent: true
    keepSpace: true
    tooltipText: root.slotTooltip
    slotSize: root.showMonitorFallback ? Style.bar.statusSlot : Style.bar.iconSlot
    fontSize: Style.bar.iconFont
    fixedWidth: root.vertical
                ? -1
                : (root.showMonitorFallback ? Style.bar.statusSlot : segGrid.implicitWidth + root.outerPad * 2)
    fixedHeight: root.vertical
                 ? (root.showMonitorFallback ? Style.bar.statusSlot : segGrid.implicitHeight + root.outerPad * 2)
                 : -1

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) { root.launchBtop(); return }
      root.toggle()
    }
    onWheelMoved: function (delta) { root.handleWheel(delta) }
    onBarChanged: Qt.callLater(root.registerCells)
    Component.onCompleted: Qt.callLater(root.registerCells)

    Grid {
      id: segGrid
      z: 1
      visible: !root.showMonitorFallback
      anchors.centerIn: parent
      columns: root.vertical ? 1 : Math.max(1, root.visibleBarCells.length)
      columnSpacing: root.segmentGap
      rowSpacing: root.segmentGap
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter

      MetricCell {
        id: cpuCell
        visible: root.segmentEnabled("cpu")
        tab: "cpu"
        metric: "cpu"
        valueText: root.cpuValueText
        valueColor: root.valueColorFor("cpu", root.cpuPct ? root.cpuPct.nonIdle : null, root.cpuHot)
      }
      MetricCell {
        id: gpuCell
        visible: root.segmentEnabled("gpu") && root.discreteGpuAvailable
        tab: "gpu"
        metric: "gpu"
        valueText: root.gpuValueText
        valueColor: root.valueColorFor("gpu", root.gpuDisplay ? root.gpuDisplay.pct : null, root.gpuHot)
      }
      MetricCell {
        id: memCell
        visible: root.segmentEnabled("memory")
        tab: "mem"
        metric: "mem"
        valueText: root.memValueText
        valueColor: root.valueColorFor("mem", root.memComp ? root.memComp.usedPct : null, root.memHot)
      }
      MetricCell {
        id: diskCell
        visible: root.segmentEnabled("disk") && root.diskAvailable
        tab: "disk"
        metric: "disk"
        valueText: root.diskValueText
        valueColor: root.valueColorFor("disk", root.diskRates ? root.diskRates.utilPct : null, root.diskHot)
      }

      // Network: glyph + inline rates; two lines on vertical bars.
      Item {
        id: netCell
        visible: root.segmentEnabled("network")
        implicitWidth: root.networkCellWidth
        implicitHeight: root.vertical ? netCol.implicitHeight : root.lineBoxHeight
        readonly property bool pressable: true
        readonly property bool interactive: true
        readonly property bool tooltipHovered: netHover.containsMouse
        function triggerPress(buttonCode) {
          if (buttonCode === Qt.RightButton) root.launchBtop()
          else root.segmentClicked("net")
        }

        Text {
          id: netLabel
          visible: !root.vertical && root.labelFor("net") !== ""
          textFormat: Text.PlainText
          text: root.labelFor("net")
          color: root.mutedLabelColor
          font.family: button.fontFamily
          font.pixelSize: root.glyphFontSize
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: netCol
          anchors.left: netLabel.visible ? netLabel.right : parent.left
          anchors.leftMargin: netLabel.visible ? root.labelGap : 0
          anchors.verticalCenter: parent.verticalCenter
          width: netLabel.visible ? root.networkRateWidth : parent.width
          spacing: 0

          Text {
            visible: root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: "↑" + root.netUpText
            color: root.valueColorFor("net", null, false)
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            font.features: ({ "tnum": 1 })
          }
          Text {
            visible: !root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: "↑ " + root.netUpText + "  ↓ " + root.netDownText
            color: root.valueColorFor("net", null, false)
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            font.features: ({ "tnum": 1 })
          }
          Text {
            visible: root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: "↓" + root.netDownText
            color: root.valueColorFor("net", null, false)
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            font.features: ({ "tnum": 1 })
          }
        }

        MouseArea {
          id: netHover
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          onEntered: if (root.bar) root.bar.showTooltip(netCell, root.tooltipFor("net"))
          onExited: if (root.bar) root.bar.hideTooltip(netCell)
        }
      }
    }
  }

  // Metric cell: this cell's glyph/letter plus a reserved value slot. It is
  // a registered click target (triggerPress) and a tooltip target
  // (tooltipHovered); the bar routes clicks and shows tooltips for it.
  component MetricCell: Item {
    id: cell

    property string tab: ""
    property string metric: ""
    property string valueText: "--"
    property color valueColor: root.barFg

    readonly property bool pressable: true
    readonly property bool interactive: true
    readonly property bool tooltipHovered: cellHover.containsMouse
    readonly property string label: root.labelFor(metric)

    function triggerPress(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchBtop()
      else root.segmentClicked(cell.tab)
    }

    implicitWidth: root.metricCellWidthFor(metric)
    implicitHeight: root.lineBoxHeight

    Text {
      id: labelText
      visible: cell.label !== ""
      textFormat: Text.PlainText
      text: cell.label
      color: root.mutedLabelColor
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: cell.valueText
      color: cell.valueColor
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
      font.features: ({ "tnum": 1 })
      horizontalAlignment: Text.AlignLeft
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: labelText.visible ? labelText.right : parent.left
      anchors.leftMargin: labelText.visible ? root.labelGap : 0
      anchors.right: parent.right
      Behavior on color { ColorAnimation { duration: 320 } }
    }

    MouseArea {
      id: cellHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: if (root.bar) root.bar.showTooltip(cell, root.tooltipFor(cell.metric))
      onExited: if (root.bar) root.bar.hideTooltip(cell)
    }
  }
}
