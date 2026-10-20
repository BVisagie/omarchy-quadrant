import QtQuick
import Quickshell
import "../lib/index.mjs" as Model

// One lazy resolver per Store. The file index follows Omarchy AppLibrary's
// apps/devices lookup without requiring its menu-only capability.
Item {
  id: root
  property bool active: false
  property var nativeAppLibrary: null
  property var desktopValues: DesktopEntries.applications.values
  readonly property var desktopIndex: Model.processAppIndex(desktopValues)
  readonly property var iconNames: {
    var names = [], seen = {}, values = desktopValues || []
    for (var i = 0; i < values.length && names.length < 512; i++) {
      var icon = String(values[i].icon || "")
      if (!icon || icon.indexOf("/") >= 0 || seen["n" + icon]) continue
      seen["n" + icon] = true
      names.push(icon)
    }
    return names
  }
  property var iconIndex: ({})
  property int iconRevision: 0
  property bool ready: false
  property bool scanDirty: false
  readonly property bool nativeIcons: !!nativeAppLibrary && typeof nativeAppLibrary.iconSource === "function"

  function entryForRow(row) { return Model.processDesktopEntry(desktopIndex, row) }
  function nameForRow(row) {
    var entry = entryForRow(row)
    return entry ? String(entry.name || "") : ""
  }
  function fileUrl(path) { return "file://" + String(path).split("/").map(encodeURIComponent).join("/") }
  function iconSource(icon) {
    var value = String(icon || "")
    // Keep this lookup live: scan completion must refresh an existing Image
    // even when neither its row nor its desktop entry has changed.
    var library = nativeAppLibrary
    if (library && typeof library.iconSource === "function") {
      var nativeSource = library.iconSource(value || "application-x-executable")
      if (nativeSource) return nativeSource
    }
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return fileUrl(value)
    if (Object.prototype.hasOwnProperty.call(iconIndex, value)) return fileUrl(iconIndex[value])
    return (value ? Quickshell.iconPath(value, true) : "") || Quickshell.iconPath("application-x-executable", true)
  }
  function iconForRow(row) {
    var entry = entryForRow(row)
    return iconSource(entry ? entry.icon : "")
  }
  function refreshIcons() {
    scanDirty = true
    if (!ready || !active) return
    iconRevision++
    var library = nativeAppLibrary
    if (library && typeof library.iconSource === "function") {
      scanDirty = false
      if (typeof library.refreshIcons === "function") library.refreshIcons()
    } else if (!scan.running) scanDelay.restart()
  }
  onActiveChanged: {
    if (active) refreshIcons()
    else scanDelay.stop()
  }
  onDesktopIndexChanged: refreshIcons()
  onNativeAppLibraryChanged: refreshIcons()
  Component.onCompleted: { ready = true; if (active) refreshIcons() }

  Timer {
    id: scanDelay
    interval: 250
    onTriggered: {
      if (!root.active || scan.running || root.nativeIcons) return
      root.scanDirty = false
      if (!root.iconNames.length) { root.iconIndex = ({}); root.iconRevision++; return }
      scan.run()
    }
  }
  Sampler {
    id: scan
    context: JSON.stringify(root.iconNames)
    command: ["python3", decodeURIComponent(String(Qt.resolvedUrl("../scripts/process-icons.py")).replace(/^file:\/\//, ""))].concat(root.iconNames)
    onResult: function(text) {
      if (activeContext !== context) return
      var data = Model.safeJson(text)
      if (data && data.ok === true && data.icons && typeof data.icons === "object") {
        root.iconIndex = data.icons
        root.iconRevision++
      }
    }
    onRunningChanged: if (!running && root.scanDirty && root.active && !root.nativeIcons) scanDelay.restart()
  }
}
