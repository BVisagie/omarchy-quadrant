import QtQuick
import qs.Ui
import qs.Commons as Commons
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
    hardwareTab: panelOpenOn("hardware"),
    expandedProcesses: panelLoader.item ? panelLoader.item.expandedProcesses === true : false,
    open: opened
  })
  onViewerStateChanged: pushViewer()
  function pushViewer() {
    if (root.store) root.store.setViewer(viewerId, viewerState)
  }
  function panelOpenOn(tab) {
    var p = panelLoader.item
    return p ? (p.opened === true && !p.settingsOpen && p.currentTab === tab) : false
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
  readonly property bool showTrends: store ? store.barStyle === "graph-text" : false
  readonly property int trendWidth: Commons.Style.space(store ? store.barGraphWidth : 32)
  readonly property string rateUnit: store ? store.rateUnit : "bytes"
  function segmentEnabled(name) {
    return store ? store.segmentEnabled(name) : false
  }

  readonly property int visibleSegmentCount: visibleBarCells.length
  readonly property bool showMonitorFallback: visibleSegmentCount === 0
  // Bar glyphs are icons, not captions: they size with the shell's body
  // text so they read at the same weight as neighbouring bar widgets,
  // while the value stays at caption.
  readonly property int glyphFontSize: Commons.Style.font.body

  // ---- colours ---------------------------------------------------------
  readonly property color barFg: root.bar ? (root.bar.barForeground || root.bar.foreground) : Commons.Color.foreground
  readonly property color barBg: root.bar ? root.bar.background : Commons.Color.background
  readonly property color barUrgent: root.bar ? root.bar.urgent : Commons.Color.urgent
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
      return Model.heatColor(pct === null ? 0 : pct, String(quietValueColor), String(Commons.Color.accent), String(barUrgent), 8)
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
  function readingTooltipFor(metric) {
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

  function tooltipFor(metric) {
    var text = readingTooltipFor(metric)
    if (!showTrends || !streamLive) return text
    if (metric === "net") {
      var points = Model.barTrendPoints(historyFor("net"), "net")
      var ceiling = Model.graphAxis(points, ["rx", "tx"], { minimumMax: 1024 }).max
      return text + "\nMinute trend: down / up · 0–" + Model.formatRateUnit(ceiling, rateUnit)
    }
    return text + "\nMinute trend: 0–100%"
  }

  readonly property string slotTooltip: {
    if (!streamLive) return "Quadrant: sampler offline"
    if (!showMonitorFallback) return ""
    return "Quadrant"
  }

  // ---- sizing ----------------------------------------------------------
  // Each value and trend has a fixed slot. Sample changes cannot move this
  // widget's neighbours or the segments within it.
  readonly property real labelGap: Commons.Style.space(3)
  readonly property real segmentGap: Commons.Style.space(8)
  readonly property real outerPad: Commons.Style.spaceReal(6)
  readonly property int verticalSlot: root.bar ? root.bar.barSize : Commons.Style.bar.sizeVertical
  readonly property var trendPalette: Model.seriesPalette(String(Commons.Color.accent), String(barUrgent), String(barFg), String(barBg))
  // Only Intel's frequency fallback can display an estimated percentage.
  // Reserve it by device capability, so a measured/estimated sample change
  // does not resize the cell.
  readonly property bool reserveEstimatePrefix: root.gpu ? root.gpu.vendor === "intel" : false

  FontMetrics { id: captionFm; font.family: button.fontFamily; font.pixelSize: Commons.Style.font.caption; font.features: ({ "tnum": 1 }) }
  FontMetrics { id: glyphFm; font.family: button.fontFamily; font.pixelSize: root.glyphFontSize }

  function labelFor(metric) { return root.vertical ? "" : Model.barLabelFor(root.barLabelsMode, metric) }
  function labelWidthFor(metric) {
    var label = labelFor(metric)
    return label === "" || glyphFm.font.pixelSize <= 0 ? 0 : Math.ceil(glyphFm.advanceWidth(label))
  }
  readonly property int lineBoxHeight: Math.ceil(Math.max(captionFm.height, root.vertical ? 0 : glyphFm.height))
  readonly property int trendHeight: root.vertical ? Commons.Style.space(14) : Math.max(2, Math.min(lineBoxHeight, root.barSize - Commons.Style.space(4)))
  // Include both directions and every compact unit; font widths can differ
  // even when the digit count is fixed. A rate never exceeds four characters.
  readonly property real rateReserve: {
    // FontMetrics methods do not notify bindings when their font changes.
    if (captionFm.font.pixelSize <= 0) return 0
    var widest = 0
    var values = ["--", ">99E"]
    for (var unit of ["B", "K", "M", "G", "T", "P", "E"]) { values.push("999" + unit); values.push("9.9" + unit) }
    for (var value of values) widest = Math.max(widest, captionFm.advanceWidth("↓" + value), captionFm.advanceWidth("↑" + value))
    return Math.ceil(widest) + 1
  }
  readonly property real rateGap: captionFm.font.pixelSize > 0 ? Math.ceil(captionFm.advanceWidth(" ")) : 0
  function valueReserveFor(metric) {
    if (captionFm.font.pixelSize <= 0) return 0
    if (metric === "net") return root.vertical ? rateReserve : rateReserve * 2 + rateGap
    return Math.ceil(captionFm.advanceWidth(metric === "gpu" && reserveEstimatePrefix ? "~100%" : "100%"))
  }
  function cellReserveFor(metric) {
    var w = valueReserveFor(metric), labelWidth = labelWidthFor(metric)
    if (labelWidth > 0) w += labelGap + labelWidth
    if (showTrends) w += trendWidth + labelGap
    return Math.ceil(w)
  }
  function valueFontSizeFor(metric) {
    if (!root.vertical) return Commons.Style.font.caption
    // Keep every visible percentage at the same size. A hidden Intel GPU
    // must not make CPU/Memory/Drives text smaller.
    var reserve = metric === "net" ? rateReserve : valueReserveFor(
      reserveEstimatePrefix && visibleBarCells.indexOf("gpu") >= 0 ? "gpu" : "cpu")
    return Math.max(1, Math.min(Commons.Style.font.caption,
      Math.floor(Commons.Style.font.caption * Math.max(1, verticalSlot) / reserve)))
  }
  readonly property real reservedWidth: {
    var cells = root.visibleBarCells, width = 0
    for (var i = 0; i < cells.length; i++) width += cellReserveFor(cells[i]) + (i > 0 ? segmentGap : 0)
    return Math.ceil(width)
  }
  function valueTextFor(metric) {
    if (metric === "cpu") return cpuValueText
    if (metric === "gpu") return gpuValueText
    if (metric === "mem") return memValueText
    return diskValueText
  }
  function percentFor(metric) {
    if (metric === "cpu") return cpuPct ? cpuPct.nonIdle : null
    if (metric === "gpu") return gpuDisplay ? gpuDisplay.pct : null
    if (metric === "mem") return memComp ? memComp.usedPct : null
    return metric === "disk" && diskRates ? diskRates.utilPct : null
  }
  function hotFor(metric) { return metric === "cpu" ? cpuHot : metric === "gpu" ? gpuHot : metric === "mem" ? memHot : metric === "disk" ? diskHot : false }
  function historyFor(metric) {
    if (!store) return []
    if (metric === "cpu") return store.cpuHistory
    if (metric === "gpu") return store.gpuHistory
    if (metric === "mem") return store.memHistory
    if (metric === "disk") return store.diskHistory
    return store.netHistory
  }

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
    Commons.Util.execArgv(["omarchy-launch-or-focus-tui", "btop"])
  }

  property real wheelAccumulator: 0
  function handleWheel(delta) {
    var r = Commons.Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = r.remainder
    var p = panelLoader.item
    if (!p || !p.opened || r.steps === 0) return
    p.stepTab(r.steps > 0 ? -1 : 1)
  }

  // Segment cells are registered as click targets after the slot button
  // so they sit above it in the bar's hit test (the bar walks targets
  // newest first).
  property var registeredCellsBar: null
  function registerCells() {
    if (registeredCellsBar && registeredCellsBar !== root.bar) unregisterCells()
    registeredCellsBar = root.bar
    if (!root.bar || typeof root.bar.registerClickTarget !== "function") return
    for (var i = 0; i < cells.count; i++) {
      var cell = cells.itemAt(i)
      if (!cell) continue
      if (typeof root.bar.unregisterClickTarget === "function") root.bar.unregisterClickTarget(cell)
      root.bar.registerClickTarget(cell)
    }
  }
  function unregisterCells() {
    if (!registeredCellsBar || typeof registeredCellsBar.unregisterClickTarget !== "function") return
    for (var i = 0; i < cells.count; i++) registeredCellsBar.unregisterClickTarget(cells.itemAt(i))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property real indicatorSlot: showMonitorFallback ? Commons.Style.bar.statusSlot : Commons.Style.bar.iconSlot
  readonly property real openPanelIndicatorWidth: Math.max(Commons.Style.space(10), Math.round(indicatorSlot * 0.55))
  readonly property real openPanelIndicatorHeight: Math.max(Commons.Style.space(10), Math.round(indicatorSlot * 0.55))

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
    slotSize: root.showMonitorFallback ? Commons.Style.bar.statusSlot : Commons.Style.bar.iconSlot
    fontSize: Commons.Style.bar.iconFont
    fixedWidth: root.vertical
                ? -1
                : (root.showMonitorFallback ? Commons.Style.bar.statusSlot : root.reservedWidth + root.outerPad * 2)
    fixedHeight: root.vertical
                 ? (root.showMonitorFallback ? Commons.Style.bar.statusSlot : segGrid.implicitHeight + root.outerPad * 2)
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
      // Horizontal bars pack cells from the left so the slack sits at the
      // end of the slot; vertical bars centre the stack in the strip.
      anchors.left: root.vertical ? undefined : parent.left
      anchors.leftMargin: root.vertical ? 0 : root.outerPad
      anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
      anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
      anchors.top: root.vertical ? parent.top : undefined
      anchors.topMargin: root.vertical ? root.outerPad : 0
      columns: root.vertical ? 1 : Math.max(1, root.visibleBarCells.length)
      columnSpacing: root.segmentGap
      rowSpacing: root.segmentGap
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignLeft
      move: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic } }

      Repeater {
        id: cells
        model: root.visibleBarCells
        onItemAdded: Qt.callLater(root.registerCells)
        onItemRemoved: function (index, item) {
          if (root.registeredCellsBar && typeof root.registeredCellsBar.unregisterClickTarget === "function")
            root.registeredCellsBar.unregisterClickTarget(item)
        }
        delegate: MetricCell {
          required property string modelData
          metric: modelData
          objectName: "barCell_" + metric
        }
      }
    }
  }

  // Click targets follow the effective order. The shell routes presses to
  // them; the plot itself never owns input or starts a sampler.
  component MetricCell: Item {
    id: cell
    property string metric: ""
    readonly property string tab: metric
    readonly property color valueColor: root.valueColorFor(metric, root.percentFor(metric), root.hotFor(metric))
    readonly property bool pressable: true
    readonly property bool interactive: true
    readonly property bool tooltipHovered: cellHover.containsMouse
    readonly property string label: root.labelFor(metric)
    readonly property color downColor: root.showTrends ? root.trendPalette.primary : root.valueColorFor("net", null, false)
    readonly property color upColor: root.showTrends ? root.trendPalette.secondary : root.valueColorFor("net", null, false)

    function triggerPress(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchBtop()
      else root.segmentClicked(cell.tab)
    }
    implicitWidth: root.vertical ? root.verticalSlot : root.cellReserveFor(metric)
    implicitHeight: root.lineBoxHeight * (metric === "net" && root.vertical ? 2 : 1)
      + (root.vertical && root.showTrends ? root.trendHeight + root.labelGap : 0)

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
    Loader {
      id: trend
      objectName: "barTrendLoader"
      active: root.showTrends
      width: root.vertical ? Math.min(root.trendWidth, cell.width) : root.trendWidth
      height: root.trendHeight
      x: root.vertical ? (cell.width - width) / 2 : labelText.visible ? labelText.width + root.labelGap : 0
      y: root.vertical ? 0 : (cell.height - height) / 2
      sourceComponent: Components.BarTrend {
        objectName: "barTrend"
        points: root.historyFor(cell.metric)
        metric: cell.metric
        color: cell.metric === "net" ? cell.downColor : cell.valueColor
        secondaryColor: cell.upColor
        gapSeconds: Model.graphGapSeconds(root.store ? root.store.barIntervalMs / 1000 : 1, false)
      }
    }
    Item {
      id: values
      x: root.vertical ? 0 : trend.active ? trend.x + trend.width + root.labelGap : labelText.visible ? labelText.width + root.labelGap : 0
      y: root.vertical && trend.active ? root.trendHeight + root.labelGap : 0
      width: root.vertical ? cell.width : root.valueReserveFor(cell.metric)
      height: root.lineBoxHeight * (cell.metric === "net" && root.vertical ? 2 : 1)
      Text {
        objectName: "barValue"
        visible: cell.metric !== "net"
        textFormat: Text.PlainText
        text: root.valueTextFor(cell.metric)
        color: cell.valueColor
        font.family: button.fontFamily
        font.pixelSize: root.valueFontSizeFor(cell.metric)
        font.features: ({ "tnum": 1 })
        anchors.fill: parent
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        Behavior on color { ColorAnimation { duration: 320 } }
      }
      Text {
        objectName: "barDown"
        visible: cell.metric === "net"
        textFormat: Text.PlainText
        text: "↓" + root.netDownText
        color: cell.downColor
        font.family: button.fontFamily
        font.pixelSize: root.valueFontSizeFor("net")
        font.features: ({ "tnum": 1 })
        width: root.vertical ? parent.width : root.rateReserve
        height: root.lineBoxHeight
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        objectName: "barUp"
        visible: cell.metric === "net"
        textFormat: Text.PlainText
        text: "↑" + root.netUpText
        color: cell.upColor
        font.family: button.fontFamily
        font.pixelSize: root.valueFontSizeFor("net")
        font.features: ({ "tnum": 1 })
        x: root.vertical ? 0 : root.rateReserve + root.rateGap
        y: root.vertical ? root.lineBoxHeight : 0
        width: root.vertical ? parent.width : root.rateReserve
        height: root.lineBoxHeight
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
      }
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
