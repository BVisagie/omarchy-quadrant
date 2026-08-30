import QtQuick
import Quickshell
import qs.Commons
import "../Theme.js" as Theme

// Process roster with app icons and a sticky row order (the merge itself
// happens in Model.mergeRoster; this component only renders).
//
// Icon/friendly-name matching is EXACT-MATCH ONLY against the normalized
// desktop-entry id, Name, Icon, and StartupWMClass — substring matching
// would let a process borrow another app's identity. The raw comm is always
// shown next to any friendly name, and every label is PlainText because
// process names are attacker-controlled.
Column {
  id: root

  property var rows: []            // [{ pid, comm, valueText, subText }]
  property string valueHeader: ""
  property string emptyText: "No activity"
  property string errorText: ""
  property color foreground: "#cacccc"
  property string fontFamily: Style.font.family

  spacing: Style.spacing.xs

  property var iconCache: ({})

  function normalizeKey(value) {
    var s = String(value || "").toLowerCase()
    var slash = s.lastIndexOf("/")
    if (slash >= 0) s = s.slice(slash + 1)
    if (s.slice(-8) === ".desktop") s = s.slice(0, -8)
    return s
  }

  // Returns { icon, name } or null. Exact matches only. Reads the cache;
  // the cache is filled in one pass by warmCache() whenever rows change, so
  // delegate bindings stay side-effect free.
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
    var next = ({})
    for (var k in root.iconCache) next[k] = root.iconCache[k]
    for (var j = 0; j < additions.length; j++) next[additions[j].key] = additions[j].value
    root.iconCache = next
  }

  onRowsChanged: warmCache()

  // Header
  Item {
    width: root.width
    implicitHeight: headerLabel.implicitHeight
    visible: root.errorText === "" && root.rows.length > 0

    Text {
      id: headerLabel
      textFormat: Text.PlainText
      text: "TOP PROCESSES"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      anchors.left: parent.left
    }

    Text {
      textFormat: Text.PlainText
      text: root.valueHeader
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      anchors.right: parent.right
      horizontalAlignment: Text.AlignRight
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.errorText !== ""
    text: root.errorText
    color: "#f7768e"
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    width: root.width
    wrapMode: Text.WordWrap
  }

  Text {
    textFormat: Text.PlainText
    visible: root.errorText === "" && root.rows.length === 0
    text: root.emptyText
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.errorText === "" ? root.rows : []

    delegate: Item {
      id: delegateRoot
      required property var modelData
      required property int index

      readonly property bool isOther: modelData && modelData.pid === 0
      readonly property var entry: isOther ? null : root.entryForComm(modelData ? modelData.comm : "")
      readonly property string displayName: {
        if (isOther) return "Other traffic"
        var raw = String(modelData && modelData.comm || "")
        if (entry && entry.name !== "" && root.normalizeKey(entry.name) !== root.normalizeKey(raw))
          return entry.name + " (" + raw + ")"
        return raw
      }

      width: root.width
      implicitHeight: rowContent.implicitHeight

      Row {
        id: rowContent
        width: parent.width
        spacing: Style.spacing.controlGap

        Image {
          source: delegateRoot.isOther
                  ? Quickshell.iconPath("network-transmit-receive", true)
                  : (delegateRoot.entry ? delegateRoot.entry.icon : Quickshell.iconPath("application-x-executable", true))
          width: Style.space(Theme.metrics.processIcon)
          height: Style.space(Theme.metrics.processIcon)
          sourceSize.width: width
          sourceSize.height: height
          anchors.verticalCenter: parent.verticalCenter
          smooth: true
        }

        Text {
          textFormat: Text.PlainText
          text: delegateRoot.displayName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: rowContent.width - Style.space(Theme.metrics.processIcon)
                 - rowContent.spacing - valueText.implicitWidth - rowContent.spacing
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: valueText
          textFormat: Text.PlainText
          text: modelData && modelData.valueText || ""
          color: Qt.darker(root.foreground, 1.2)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
