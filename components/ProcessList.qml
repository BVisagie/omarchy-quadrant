import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model

// Process roster with app icons, a sparkline per row, sortable header and
// a single cursor shared by mouse and keyboard. The sticky row order comes
// from Model.mergeRoster in the store; this component only renders and
// re-sorts a copy when the header is clicked.
//
// Icon/friendly-name matching is EXACT-MATCH ONLY against the normalized
// desktop-entry id, Name, Icon, and StartupWMClass — substring matching
// would let a process borrow another app's identity. Every label is
// PlainText because process names are attacker-controlled.
//
//   rows — [{ pid, comm, valueText, sortKey, history, hint }]
Column {
  id: root

  property var rows: []
  property string valueHeader: ""
  property string emptyText: "No activity"
  property string errorText: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool showSparkline: true
  property real sparklineMax: 0
  // "sticky" keeps the store's order; "value" and "name" re-sort locally.
  property string sortMode: "sticky"
  property int cursorIndex: -1
  property bool cursorActive: false

  signal rowHovered(int index, bool isHovered)

  readonly property color dim: Model.dimColor(String(foreground), String(Color.background))
  readonly property color sparkColor: Color.accent

  spacing: Style.spacing.xxs

  readonly property var displayRows: {
    var src = Array.isArray(rows) ? rows.slice() : []
    if (sortMode === "value") src.sort(function (a, b) { return (Number(b.sortKey) || 0) - (Number(a.sortKey) || 0) })
    else if (sortMode === "name") src.sort(function (a, b) { return String(a.comm || "").toLowerCase() < String(b.comm || "").toLowerCase() ? -1 : 1 })
    return src
  }

  function cycleSort() {
    sortMode = sortMode === "sticky" ? "value" : sortMode === "value" ? "name" : "sticky"
  }

  // ---- desktop-entry lookup (bounded cache) ------------------------------
  property var iconCache: ({})
  property int iconCacheSize: 0

  function normalizeKey(value) {
    var s = String(value || "").toLowerCase()
    var slash = s.lastIndexOf("/")
    if (slash >= 0) s = s.slice(slash + 1)
    if (s.slice(-8) === ".desktop") s = s.slice(0, -8)
    return s
  }

  function entryForComm(comm) {
    var key = normalizeKey(comm)
    if (key === "") return null
    var hit = root.iconCache[key]
    return hit === undefined ? null : hit
  }

  function lookupEntry(key) {
    var entry = DesktopEntries.byId(key)
    if (entry) return entry
    var values = DesktopEntries.applications.values || []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e) continue
      if (normalizeKey(e.name) === key
          || normalizeKey(e.icon) === key
          || normalizeKey(e.startupClass) === key)
        return e
    }
    return null
  }

  function warmCache() {
    var additions = []
    for (var i = 0; i < rows.length; i++) {
      var key = normalizeKey(rows[i] && rows[i].comm)
      if (key === "" || root.iconCache[key] !== undefined) continue
      var entry = lookupEntry(key)
      var found = null
      if (entry) {
        var icon = String(entry.icon || "")
        var source = ""
        if (icon.charAt(0) === "/") source = Util.fileUrl(icon)
        else if (icon !== "") source = Quickshell.iconPath(icon, true)
        if (source === "") source = Quickshell.iconPath("application-x-executable", true)
        found = { icon: source, name: String(entry.name || "") }
      }
      additions.push({ key: key, value: found })
    }
    if (additions.length === 0) return
    // The cache only ever grows with new comm names; cap it so a machine
    // that churns through thousands of short-lived names cannot grow it
    // without bound.
    var next = ({})
    var size = 0
    if (root.iconCacheSize + additions.length <= 256) {
      for (var k in root.iconCache) { next[k] = root.iconCache[k]; size++ }
    }
    for (var j = 0; j < additions.length; j++) { next[additions[j].key] = additions[j].value; size++ }
    root.iconCache = next
    root.iconCacheSize = size
  }

  onRowsChanged: warmCache()

  // ---- header ------------------------------------------------------------
  Item {
    width: root.width
    implicitHeight: headerLabel.implicitHeight
    visible: root.errorText === "" && root.rows.length > 0

    Text {
      id: headerLabel
      textFormat: Text.PlainText
      text: "TOP PROCESSES"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.left: parent.left
    }

    Text {
      id: sortHint
      textFormat: Text.PlainText
      text: root.sortMode === "sticky" ? "" : (root.sortMode === "value" ? "by value" : "by name")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.left: headerLabel.right
      anchors.leftMargin: Style.space(8)
    }

    Text {
      id: valueHeaderText
      textFormat: Text.PlainText
      text: root.valueHeader
      color: headerMouse.containsMouse ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.right: parent.right
      horizontalAlignment: Text.AlignRight
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
    visible: root.errorText !== ""
    text: root.errorText
    color: Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    width: root.width
    wrapMode: Text.WordWrap
  }

  Text {
    textFormat: Text.PlainText
    visible: root.errorText === "" && root.rows.length === 0
    text: root.emptyText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.errorText === "" ? root.displayRows : []

    delegate: CursorSurface {
      id: delegateRoot
      required property var modelData
      required property int index

      readonly property bool isOther: modelData && modelData.pid === 0
      readonly property var entry: isOther ? null : root.entryForComm(modelData ? modelData.comm : "")
      readonly property string displayName: {
        if (isOther) return "Other traffic"
        var raw = String(modelData && modelData.comm || "")
        if (entry && entry.name !== "") return entry.name
        return raw
      }
      readonly property string hint: {
        if (!modelData) return ""
        var bits = []
        if (modelData.pid > 0) bits.push("pid " + modelData.pid)
        if (modelData.hint) bits.push(String(modelData.hint))
        return bits.join(" · ")
      }

      width: root.width
      implicitHeight: rowContent.implicitHeight + Style.space(4)
      hasCursor: root.cursorActive && root.cursorIndex === index
      foreground: root.foreground
      color: hasCursor ? fill : "transparent"

      Row {
        id: rowContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(4)
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.controlGap

        Image {
          source: delegateRoot.isOther
                  ? Quickshell.iconPath("network-transmit-receive", true)
                  : (delegateRoot.entry ? delegateRoot.entry.icon : Quickshell.iconPath("application-x-executable", true))
          width: Style.space(16)
          height: Style.space(16)
          sourceSize.width: width
          sourceSize.height: height
          anchors.verticalCenter: parent.verticalCenter
          smooth: true
        }

        Text {
          id: nameText
          textFormat: Text.PlainText
          text: delegateRoot.displayName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: Math.max(0, rowContent.width - Style.space(16) - rowContent.spacing * (root.showSparkline ? 3 : 2)
                 - valueText.implicitWidth - (root.showSparkline ? spark.width : 0))
          anchors.verticalCenter: parent.verticalCenter
        }

        Sparkline {
          id: spark
          visible: root.showSparkline && !delegateRoot.isOther
          values: delegateRoot.modelData && delegateRoot.modelData.history ? delegateRoot.modelData.history : []
          maxValue: root.sparklineMax
          color: root.sparkColor
          width: Style.space(36)
          height: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: valueText
          textFormat: Text.PlainText
          text: delegateRoot.modelData && delegateRoot.modelData.valueText || ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.features: ({ "tnum": 1 })
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.rowHovered(delegateRoot.index, true)
        onExited: root.rowHovered(delegateRoot.index, false)
      }

      PanelToolTip {
        visible: delegateRoot.hasCursor && delegateRoot.hint !== ""
        text: delegateRoot.hint
        fontFamily: root.fontFamily
      }
    }
  }
}
