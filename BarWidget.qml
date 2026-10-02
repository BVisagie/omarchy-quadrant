import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Theme.js" as Theme
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
  Component.onDestruction: if (store) store.clearViewer(viewerId)

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
    diskTab: panelOpenOn("disk"),
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
  function segmentEnabled(name) {
    return store ? store.segmentEnabled(name) : false
  }

  readonly property int visibleSegmentCount: visibleBarCells.length
  readonly property bool showMonitorFallback: visibleSegmentCount === 0
  // Bar glyphs are icons, not captions: they size with the shell's body
  // text so they read at the same weight as neighbouring bar widgets,
  // while the percentage stays at caption.
  readonly property int glyphFontSize: Style.font.body

  readonly property var themePal: Theme.barPaletteFor(
    String(root.bar ? (root.bar.barForeground || root.bar.foreground) : Color.foreground),
    String(Color.accent),
    String(root.bar ? root.bar.urgent : Color.urgent)
  )
  readonly property bool cpuHot: cpuPct !== null && cpuPct.nonIdle >= 90
  readonly property bool memHot: memComp !== null && memComp.usedPct >= 90
  readonly property bool gpuHot: gpuDisplay !== null && gpuDisplay.pct >= 90
  readonly property bool diskHot: diskRates !== null && diskRates.utilPct >= 90
  readonly property string cpuValueText: cpuPct ? Model.formatPct(cpuPct.nonIdle) : "--"
  readonly property string memValueText: memComp ? Model.formatPct(memComp.usedPct) : "--"
  readonly property string gpuValueText: {
    if (!gpuDisplay) return "--"
    return (gpuDisplay.estimated ? "~" : "") + Model.formatPct(gpuDisplay.pct)
  }
  readonly property string diskValueText: diskRates ? Model.formatPct(diskRates.utilPct) : "--"
  readonly property color hotTextColor: {
    if (barPaletteMode === "vivid") return Theme.series.cpuSteal
    return themePal.urgent
  }
  readonly property color mutedLabelColor: {
    var c = Theme.mutedFor(String(root.bar ? (root.bar.barForeground || root.bar.foreground) : Color.foreground))
    return c || Color.foreground
  }
  // Single caption/glyph line. Vertical bars drop the glyph, so they
  // keep the caption height. Network's two-line vertical form can be taller.
  readonly property int lineBoxHeight: {
    if (root.vertical) return pctSizer.implicitHeight
    var g = Math.max(cpuGlyphSizer.implicitHeight, netGlyphSizer.implicitHeight)
    return g > pctSizer.implicitHeight ? g : pctSizer.implicitHeight
  }
  // Each cell is its own glyph (or letter) plus one reserved value slot.
  function metricLabelWidthFor(metric) {
    if (root.vertical || root.barLabelsMode === "none") return 0
    if (metric === "cpu") return cpuGlyphSizer.implicitWidth
    if (metric === "gpu") return gpuGlyphSizer.implicitWidth
    if (metric === "mem") return memGlyphSizer.implicitWidth
    if (metric === "disk") return diskGlyphSizer.implicitWidth
    if (metric === "net") return netGlyphSizer.implicitWidth
    return 0
  }
  function metricValueWidthFor(metric) {
    var w = pctSizer.implicitWidth
    if (metric === "gpu" && root.reserveEstimatePrefix)
      w += tildeSizer.implicitWidth
    return Math.ceil(w)
  }
  function metricCellWidthFor(metric) {
    var w = metricValueWidthFor(metric)
    var lw = metricLabelWidthFor(metric)
    if (lw > 0)
      w += Style.space(Theme.metrics.barLabelGap) + lw
    if (root.vertical && root.bar)
      return Math.min(w, root.bar.barSize)
    return w
  }
  readonly property real networkRateWidth: Math.ceil(netSizer.implicitWidth) + 1
  readonly property real networkCellWidth: {
    var w = root.networkRateWidth
    var lw = metricLabelWidthFor("net")
    if (lw > 0)
      w += Style.space(Theme.metrics.barLabelGap) + lw
    if (root.vertical)
      return Math.min(w, root.verticalSlot)
    return w
  }
  // Only an Intel GPU reporting frequency-derived load ever prefixes "~".
  readonly property bool reserveEstimatePrefix: {
    if (!root.segmentEnabled("gpu") || !root.discreteGpuAvailable) return false
    return root.gpu && root.gpu.vendor === "intel"
  }
  readonly property int verticalSlot: root.bar ? root.bar.barSize : Style.bar.sizeVertical

  readonly property string tooltipLine: {
    if (!streamLive) return "Quadrant: sampler offline"
    var parts = []
    if (segmentEnabled("cpu") && cpuPct)
      parts.push(Model.cpuBarTooltip(cpuPct))
    if (segmentEnabled("gpu") && discreteGpuAvailable && gpuDisplay)
      parts.push("GPU " + Model.formatPct(gpuDisplay.pct) + (gpuDisplay.estimated ? " (freq)" : ""))
    if (segmentEnabled("memory") && memComp)
      parts.push("MEMORY " + Model.formatPct(memComp.usedPct))
    if (segmentEnabled("disk") && diskAvailable && diskRates)
      parts.push("DRIVES " + Model.formatPct(diskRates.utilPct)
        + "  R " + Model.formatRate(diskRates.readBps)
        + "  W " + Model.formatRate(diskRates.writeBps))
    if (segmentEnabled("network") && ifaceRates)
      parts.push("↑ " + Model.formatRate(ifaceRates.txBps) + " ↓ " + Model.formatRate(ifaceRates.rxBps))
    return parts.length > 0 ? parts.join("  ·  ") : "Quadrant"
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

  // Click on a segment: open the panel on that tab; clicking the slot
  // elsewhere toggles the panel on the last-used tab. Segment MouseAreas
  // sit above WidgetButton's own MouseArea; ignoreNextToggle drops the
  // button press when both still fire.
  property bool ignoreNextToggle: false

  function noteSegmentPress() {
    ignoreNextToggle = true
  }

  function segmentClicked(tab) {
    ignoreNextToggle = true
    var p = panelLoader.item
    if (!p) {
      Qt.callLater(function () { root.ignoreNextToggle = false })
      return
    }
    if (p.opened) {
      if (p.currentTab === tab) p.close()
      else p.currentTab = tab
    } else {
      p.showTab(tab)
    }
    Qt.callLater(function () { root.ignoreNextToggle = false })
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

  // ---- bar slot ----
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showMonitorFallback ? Theme.barGlyphs.monitor : ""
    hasVisualContent: true
    keepSpace: true
    tooltipText: root.tooltipLine
    // tooltipLine is rates/percentages, never process comm. The shell's
    // WidgetButton tooltip Text is already PlainText.
    // Empty-segment fallback is a compact status item. It keeps the shell's
    // standard icon canvas/font while avoiding icon-slot padding.
    slotSize: root.showMonitorFallback ? Style.bar.statusSlot : Style.bar.iconSlot
    fontSize: Style.bar.iconFont
    fixedWidth: root.vertical
                ? -1
                : (root.showMonitorFallback
                   ? Style.bar.statusSlot
                   : segGrid.implicitWidth + Style.spaceReal(Theme.metrics.barOuterPad) * 2)
    fixedHeight: root.vertical
                 ? (root.showMonitorFallback
                    ? Style.bar.statusSlot
                    : segGrid.implicitHeight + Style.spaceReal(Theme.metrics.barOuterPad) * 2)
                 : -1

    onPressed: function(buttonCode) {
      if (buttonCode !== Qt.LeftButton) return
      if (root.ignoreNextToggle) {
        root.ignoreNextToggle = false
        return
      }
      root.toggle()
    }

    // Shared sizers: cell width is locked to glyph + "100%" so digits
    // never resize the slot. The "~" estimate prefix is reserved only
    // when an Intel GPU can show it. Hidden, not Grid children.
    Text {
      id: pctSizer
      visible: false
      textFormat: Text.PlainText
      text: "100%"
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: tildeSizer
      visible: false
      textFormat: Text.PlainText
      text: "~"
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: cpuGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "cpu")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: gpuGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "gpu")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: memGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "mem")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: diskGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "disk")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: netGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "net")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Grid {
      id: segGrid
      z: 1
      visible: !root.showMonitorFallback
      anchors.centerIn: parent
      columns: root.vertical ? 1 : Math.max(1, root.visibleBarCells.length)
      columnSpacing: Style.space(Theme.metrics.barSegmentGap)
      rowSpacing: Style.space(Theme.metrics.barSegmentGap)
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter

      MetricCell {
        visible: root.segmentEnabled("cpu")
        tab: "cpu"
        metric: "cpu"
        valueText: root.cpuValueText
        hot: root.cpuHot
      }

      MetricCell {
        visible: root.segmentEnabled("gpu") && root.discreteGpuAvailable
        tab: "gpu"
        metric: "gpu"
        valueText: root.gpuValueText
        hot: root.gpuHot
      }

      MetricCell {
        visible: root.segmentEnabled("memory")
        tab: "mem"
        metric: "mem"
        valueText: root.memValueText
        hot: root.memHot
      }

      MetricCell {
        visible: root.segmentEnabled("disk") && root.diskAvailable
        tab: "disk"
        metric: "disk"
        valueText: root.diskValueText
        hot: root.diskHot
      }

      // ---- Network: glyph + inline rates; two-line only on vertical bars ----
      Item {
        visible: root.segmentEnabled("network")
        implicitWidth: root.networkCellWidth
        implicitHeight: root.vertical ? netCol.implicitHeight : root.lineBoxHeight

        Text {
          id: netSizer
          visible: false
          textFormat: Text.PlainText
          text: root.vertical ? "↓999T" : "↑ 999T  ↓ 999T"
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: netLabel
          visible: !root.vertical && Theme.barLabelFor(root.barLabelsMode, "net") !== ""
          textFormat: Text.PlainText
          text: Theme.barLabelFor(root.barLabelsMode, "net")
          color: root.mutedLabelColor
          font.family: button.fontFamily
          font.pixelSize: root.glyphFontSize
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: netCol
          anchors.left: netLabel.visible ? netLabel.right : parent.left
          anchors.leftMargin: netLabel.visible ? Style.space(Theme.metrics.barLabelGap) : 0
          anchors.verticalCenter: parent.verticalCenter
          width: netLabel.visible ? root.networkRateWidth : parent.width
          spacing: 0

          Text {
            visible: root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: "↑" + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.txBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: !root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: "↑ " + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.txBps) : "--")
                 + "  ↓ " + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.rxBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: "↓" + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.rxBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          acceptedButtons: Qt.LeftButton
          onPressed: root.noteSegmentPress()
          onClicked: root.segmentClicked("net")
        }
      }
    }
  }

  // Metric cell: this cell's glyph/letter + a reserved percentage slot.
  // The value hugs the icon; leftover slot width sits after the digits.
  component MetricCell: Item {
    id: cell

    property string tab: ""
    property string metric: ""
    property string valueText: "--"
    property bool hot: false

    readonly property string label: root.vertical ? "" : Theme.barLabelFor(root.barLabelsMode, metric)
    readonly property color valueColor: cell.hot ? root.hotTextColor : button.foreground

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
      horizontalAlignment: Text.AlignLeft
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: labelText.visible ? labelText.right : parent.left
      anchors.leftMargin: labelText.visible ? Style.space(Theme.metrics.barLabelGap) : 0
      anchors.right: parent.right
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: false
      acceptedButtons: Qt.LeftButton
      onPressed: root.noteSegmentPress()
      onClicked: root.segmentClicked(cell.tab)
    }
  }
}
