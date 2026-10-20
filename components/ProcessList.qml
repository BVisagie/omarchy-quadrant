import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui
import "../lib/index.mjs" as Model

// Complete groups are searched before the 256-row presentation cap. ListView
// creates only visible delegates; compact lists keep the store's sticky order.
// Desktop matches are exact and indexed once per inventory change. No clipboard
// data is requested here; TextField paste requires the user's normal shortcut.
Column {
  id: root
  // No disclosures here; keep the details scan independent of live delegates.
  readonly property bool detailsLeaf: true

  property var panel: null
  property bool active: true
  property var rows: []
  property var expandedRows: []
  property bool expandable: false
  property bool expandedReady: false
  property bool expanded: false
  property string query: ""
  property string scopeText: ""
  property string title: "Top processes"
  property string valueHeader: ""
  property string emptyText: "No activity"
  property string errorText: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  property bool showSparkline: true
  property real sparklineMax: 0
  property string sortMode: "sticky"
  property int cursorIndex: -1
  property bool cursorActive: false
  property var selectedRow: null
  property bool pointerPrimed: false
  property point lastPointer: Qt.point(0, 0)
  property var presentedRows: []
  property var pendingViewport: null
  property string presentedQuery: ""
  property string presentedSort: "sticky"
  property bool presentedExpanded: false
  readonly property bool searchFocused: searchField.activeFocus
  readonly property int rowHeight: Commons.Style.space(42)
  readonly property int displayLimit: 256
  readonly property int visibleRowCount: displayRows.length
  readonly property color dim: Model.dimColor(String(foreground), String(Commons.Color.background))
  readonly property var sourceRows: expanded ? (expandedReady ? expandedRows : []) : rows
  readonly property string effectiveSort: expanded && sortMode === "sticky" ? "value" : sortMode
  readonly property var results: Model.filterProcessGroups(sourceRows, expanded ? query : "", desktopNames, displayLimit, effectiveSort)
  readonly property var displayRows: results.rows

  spacing: Commons.Style.spacing.xxs

  function cycleSort() {
    sortMode = expanded ? (effectiveSort === "value" ? "name" : "value")
                       : sortMode === "sticky" ? "value" : sortMode === "value" ? "name" : "sticky"
  }
  function focusSearch() {
    if (!expandable) return
    expanded = true
    Qt.callLater(function () { searchField.forceActiveFocus(); ensureCursorVisible() })
  }
  function leaveSearch() {
    searchField.focus = false
    if (panel && panel.focusProcessKeys) panel.focusProcessKeys()
  }
  function enterResults() {
    if (displayRows.length === 0 || errorText !== "") return
    leaveSearch()
    selectRow(0)
  }
  function suspendSearch() { searchField.focus = false }
  function reset() { expanded = false; query = ""; suspendSearch(); clearCursor() }
  function clearCursor() { cursorActive = false; cursorIndex = -1; selectedRow = null }
  function selectRow(index, reveal) {
    if (index < 0 || index >= displayRows.length || errorText !== "") { clearCursor(); return }
    if (panel && panel.currentActions && panel.currentActions.keyboardActive) panel.currentActions.leaveFocus()
    selectedRow = displayRows[index]
    cursorIndex = index
    cursorActive = true
    if (reveal !== false) ensureCursorVisible()
  }
  function moveCursor(delta) {
    pointerPrimed = false
    if (!displayRows.length || errorText !== "") { clearCursor(); return }
    selectRow(cursorIndex < 0 ? (delta > 0 ? 0 : displayRows.length - 1)
                            : Math.max(0, Math.min(displayRows.length - 1, cursorIndex + delta)))
  }
  function reconcileCursor() {
    if (!cursorActive || !selectedRow) return
    for (var i = 0; i < displayRows.length; i++) {
      if (Model.sameProcessSelection(selectedRow, displayRows[i])) { selectRow(i, false); return }
    }
    clearCursor()
  }
  function cursorY() { return list.y + (cursorIndex < 0 ? 0 : cursorIndex * rowHeight - list.contentY) }
  function ensureCursorVisible() {
    if (pendingViewport) { pendingViewport.revealCursor = true; return }
    if (cursorIndex >= 0) list.positionViewAtIndex(cursorIndex, ListView.Contain)
    if (panel && panel.scrollProcessCursor) panel.scrollProcessCursor(root)
  }
  function captureViewport() {
    var y = list ? Math.max(0, list.contentY - list.originY) : 0
    var index = Math.floor(y / rowHeight)
    return { anchor: presentedRows[index] || null, offset: y - index * rowHeight,
             y: y, filterChanged: false, revealCursor: false }
  }
  function updatePresentedRows() {
    pointerPrimed = false
    // Keep the old model until its visible anchor has been captured. Multiple
    // updates before layout share that snapshot rather than capturing a reset.
    if (!pendingViewport) pendingViewport = captureViewport()
    var changed = presentedQuery !== query || presentedSort !== effectiveSort || presentedExpanded !== expanded
    pendingViewport.filterChanged = pendingViewport.filterChanged || changed
    presentedQuery = query
    presentedSort = effectiveSort
    presentedExpanded = expanded
    reconcileCursor()
    presentedRows = displayRows
    Qt.callLater(restoreViewport)
  }
  function restoreViewport() {
    var viewport = pendingViewport
    if (!viewport || !list) return
    list.forceLayout()
    var y = viewport.y
    if (viewport.filterChanged && !cursorActive) y = 0
    else if (viewport.anchor) {
      for (var i = 0; i < presentedRows.length; i++) {
        if (Model.sameProcessRow(viewport.anchor, presentedRows[i])) {
          var anchorY = i * rowHeight + viewport.offset
          // Follow nearby changes without chasing volatile ranks across screens.
          if (Math.abs(anchorY - viewport.y) < list.height) y = anchorY
          break
        }
      }
    }
    list.contentY = list.originY + Math.max(0, Math.min(y, list.contentHeight - list.height))
    pendingViewport = null
    // A sample reconciles identity without moving the cursor or the viewport
    // to it. Only an explicit navigation/filter action requests a reveal.
    if (viewport.revealCursor || viewport.filterChanged) ensureCursorVisible()
  }
  onDisplayRowsChanged: updatePresentedRows()
  function pointerMoved(item, mouse) {
    var point = item.mapToItem(root, mouse.x, mouse.y)
    var moved = pointerPrimed && (Math.abs(point.x - lastPointer.x) > 1 || Math.abs(point.y - lastPointer.y) > 1)
    if (!pointerPrimed || moved) lastPointer = point
    pointerPrimed = true
    return moved
  }
  onErrorTextChanged: if (errorText !== "") clearCursor()
  onActiveChanged: if (!active) { suspendSearch(); clearCursor() }
  onExpandedChanged: if (!expanded) { query = ""; leaveSearch() }

  // Build a finite index of installed entries, not a scan for each process
  // on every sample. Only visible delegates resolve icons, with a 256-name
  // FIFO cache; search uses names without loading icon paths.
  readonly property var desktopValues: DesktopEntries.applications.values
  property var desktopIndex: ({})
  property var desktopNames: ({})
  property var iconCache: ({})
  property var iconOrder: []
  function normalizeKey(value) {
    var s = String(value || "").toLowerCase()
    s = s.slice(s.lastIndexOf("/") + 1)
    return s.slice(-8) === ".desktop" ? s.slice(0, -8) : s
  }
  function rebuildDesktopIndex() {
    var index = {}, names = {}
    var values = desktopValues || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e) continue
      var keys = [e.id, e.name, e.icon, e.startupClass]
      for (var j = 0; j < keys.length; j++) {
        var key = normalizeKey(keys[j])
        if (key && !index["n" + key]) { index["n" + key] = e; names["n" + key] = String(e.name || "") }
      }
    }
    desktopIndex = index
    desktopNames = names
    iconCache = ({})
    iconOrder = []
  }
  onDesktopValuesChanged: rebuildDesktopIndex()
  Component.onCompleted: rebuildDesktopIndex()
  function entryForComm(comm) { return desktopIndex["n" + normalizeKey(comm)] || null }
  function iconForComm(comm) {
    var key = "n" + normalizeKey(comm)
    if (iconCache[key] !== undefined) return iconCache[key]
    var entry = entryForComm(comm)
    var icon = entry ? String(entry.icon || "") : ""
    var source = icon.charAt(0) === "/" ? Commons.Util.fileUrl(icon) : icon ? Quickshell.iconPath(icon, true) : ""
    if (!source) source = Quickshell.iconPath("application-x-executable", true)
    // Mutate only the lookup cache, not a binding dependency of delegates.
    if (iconOrder.length >= 256) delete iconCache[iconOrder.shift()]
    iconCache[key] = source
    iconOrder.push(key)
    return source
  }

  Item {
    width: root.width
    implicitHeight: Math.max(headerLabel.implicitHeight, expandButton.implicitHeight)
    Text {
      id: headerLabel
      textFormat: Text.PlainText
      text: root.expanded ? "Processes" : root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }
    Ui.Button {
      id: expandButton
      objectName: "processExpand"
      visible: root.expandable
      text: root.expanded ? "Show less" : "Show all"
      anchors.right: parent.right
      onClicked: {
        if (root.expanded) root.expanded = false
        else root.focusSearch()
      }
    }
  }

  Row {
    visible: root.expanded
    width: root.width
    spacing: Commons.Style.space(6)
    Ui.TextField {
      id: searchField
      objectName: "processSearch"
      width: parent.width - clearButton.width - parent.spacing
      text: root.query
      placeholderText: "Name or PID  ·  / to search"
      maximumLength: 128
      foreground: root.foreground
      onTextEdited: root.query = text
      Keys.onEscapePressed: function (event) {
        if (root.query !== "") root.query = ""
        else root.leaveSearch()
        event.accepted = true
      }
      Keys.onTabPressed: function (event) {
        root.leaveSearch()
        if (root.panel && root.panel.switchPanel) root.panel.switchPanel(1)
        event.accepted = true
      }
      Keys.onBacktabPressed: function (event) {
        root.leaveSearch()
        if (root.panel && root.panel.switchPanel) root.panel.switchPanel(-1)
        event.accepted = true
      }
      Keys.onDownPressed: function (event) { root.enterResults(); event.accepted = true }
      Keys.onReturnPressed: function (event) { root.enterResults(); event.accepted = true }
      Keys.onEnterPressed: function (event) { root.enterResults(); event.accepted = true }
    }
    Ui.Button {
      id: clearButton
      objectName: "processClear"
      text: "Clear"
      enabled: root.query !== ""
      onClicked: { root.query = ""; searchField.forceActiveFocus() }
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.scopeText !== ""
    text: root.scopeText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    width: root.width
    wrapMode: Text.WordWrap
  }

  Item {
    visible: root.errorText === "" && root.sourceRows.length > 0
    width: root.width
    implicitHeight: sortLabel.implicitHeight
    Text {
      id: sortLabel
      textFormat: Text.PlainText
      text: root.expanded ? root.results.matches + " matching groups · " + root.displayRows.length + " shown" : root.displayRows.length + " groups"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      anchors.left: parent.left
      width: Math.max(0, parent.width - valueHeaderText.width - Commons.Style.space(8))
      elide: Text.ElideRight
    }
    Text {
      id: valueHeaderText
      textFormat: Text.PlainText
      text: root.valueHeader + (root.effectiveSort === "sticky" ? " ↕" : root.effectiveSort === "value" ? " ↓" : " A–Z")
      color: headerMouse.containsMouse ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
      anchors.right: parent.right
    }
    MouseArea {
      id: headerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.cycleSort()
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.errorText !== "" || root.displayRows.length === 0
    text: root.errorText !== "" ? root.errorText : root.expanded && !root.expandedReady ? "Collecting full process roster…"
          : root.expanded && root.query !== "" ? "No matching processes in the eligible roster" : root.emptyText
    color: root.errorText !== "" ? Commons.Color.urgent : root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.bodySmall
    width: root.width
    wrapMode: Text.WordWrap
  }

  ListView {
    id: list
    objectName: "processRows"
    width: root.width
    height: root.errorText !== "" ? 0 : Math.min(contentHeight, root.expanded ? Commons.Style.space(336) : root.displayRows.length * root.rowHeight)
    model: root.presentedRows
    clip: true
    reuseItems: true
    cacheBuffer: 0
    interactive: root.expanded && contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    Controls.ScrollBar.vertical: Controls.ScrollBar { }

    delegate: Ui.CursorSurface {
      id: delegateRoot
      required property var modelData
      required property int index
      readonly property bool isOther: modelData && modelData.pid === 0
      readonly property var entry: isOther ? null : root.entryForComm(modelData ? modelData.comm : "")
      readonly property string displayName: isOther ? "Other traffic" : entry && entry.name ? String(entry.name) : String(modelData.comm || "")
      readonly property string memberText: {
        var r = modelData
        if (r.matchedPids && r.matchedPids.length) return "PID " + r.matchedPids.slice(0, 3).join(", ") + (r.matchedPids.length > 3 ? "…" : "") + " matched"
        if (r.n > 1) return r.n + " processes · name group"
        return r.pid > 0 ? "PID " + r.pid : "Unattributed traffic"
      }
      readonly property string coverageText: modelData.known !== undefined && modelData.known < modelData.n
                                             ? " · " + modelData.known + "/" + modelData.n + " measured" : ""
      width: list.width - Commons.Style.space(8)
      height: root.rowHeight
      hasCursor: root.cursorActive && root.cursorIndex === index
      foreground: root.foreground
      color: hasCursor ? fill : "transparent"

      Image {
        id: appIcon
        source: delegateRoot.isOther ? Quickshell.iconPath("network-transmit-receive", true) : root.iconForComm(delegateRoot.modelData.comm)
        width: Commons.Style.space(16)
        height: width
        sourceSize.width: width
        sourceSize.height: height
        anchors.left: parent.left
        anchors.leftMargin: Commons.Style.space(4)
        anchors.top: parent.top
        anchors.topMargin: Commons.Style.space(5)
        smooth: true
      }
      Text {
        id: nameText
        textFormat: Text.PlainText
        text: delegateRoot.displayName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.body
        elide: Text.ElideRight
        anchors.left: appIcon.right
        anchors.leftMargin: Commons.Style.space(6)
        anchors.top: appIcon.top
        width: Math.max(0, valueText.x - x - (countBadge.visible ? countBadge.implicitWidth + Commons.Style.space(6) : 0) - Commons.Style.space(6))
      }
      Text {
        id: countBadge
        textFormat: Text.PlainText
        visible: delegateRoot.modelData.n > 1
        text: "×" + (delegateRoot.modelData.n || 1)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        anchors.left: nameText.right
        anchors.leftMargin: Commons.Style.space(4)
        anchors.baseline: nameText.baseline
      }
      Text {
        id: valueText
        textFormat: Text.PlainText
        text: delegateRoot.modelData.valueText || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.bodySmall
        font.features: ({ "tnum": 1 })
        horizontalAlignment: Text.AlignRight
        width: Math.min(implicitWidth, parent.width * 0.48)
        elide: Text.ElideLeft
        anchors.right: parent.right
        anchors.rightMargin: Commons.Style.space(4)
        anchors.top: appIcon.top
      }
      Text {
        id: memberLabel
        textFormat: Text.PlainText
        text: delegateRoot.memberText + delegateRoot.coverageText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
        anchors.left: nameText.left
        anchors.top: nameText.bottom
        width: Math.max(0, parent.width - x - secondary.width - (spark.visible ? spark.width + Commons.Style.space(6) : 0) - Commons.Style.space(8))
      }
      Sparkline {
        id: spark
        visible: root.showSparkline && !delegateRoot.isOther
        values: delegateRoot.modelData.history || []
        maxValue: root.sparklineMax
        color: Commons.Color.accent
        width: Commons.Style.space(36)
        height: Commons.Style.space(12)
        anchors.right: secondary.left
        anchors.rightMargin: Commons.Style.space(6)
        anchors.verticalCenter: memberLabel.verticalCenter
      }
      Text {
        id: secondary
        textFormat: Text.PlainText
        text: delegateRoot.modelData.secondaryValueText || ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        font.features: ({ "tnum": 1 })
        horizontalAlignment: Text.AlignRight
        width: Math.min(implicitWidth, parent.width * 0.4)
        elide: Text.ElideLeft
        anchors.right: valueText.right
        anchors.top: memberLabel.top
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        // Scrolling/reordering under a stationary pointer must not steal
        // the keyboard's logical target. Select on deliberate movement.
        onPositionChanged: function (mouse) {
          if (root.pointerMoved(delegateRoot, mouse)) root.selectRow(delegateRoot.index)
        }
      }
      Ui.PanelToolTip {
        visible: delegateRoot.hasCursor
        text: delegateRoot.displayName + " · " + delegateRoot.memberText + delegateRoot.coverageText
              + (delegateRoot.modelData.hint ? " · " + delegateRoot.modelData.hint : "")
        fontFamily: root.fontFamily
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.expanded && root.results.limited
    text: "Showing the first " + root.displayLimit + " matching groups. Refine the search to see others."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    width: root.width
    wrapMode: Text.WordWrap
  }
}
