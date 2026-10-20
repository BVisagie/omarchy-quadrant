//@ pragma OmarchyLoadPatch
import QtQuick
import Quickshell
import Quickshell.Io
import QtTest
import "components" as Components
import "lib/index.mjs" as Model

ShellRoot {
  Window {
    id: win
    visible: true; width: 440; height: 400
    Components.ProcessApps {
      id: apps
      desktopValues: [
        { id: "t3code", name: "T3 Code Nightly", startupClass: "t3code", icon: "quadrant-test-t3", command: ["t3code-nightly", "%U"] },
        { id: "brave-origin", name: "Brave Origin", icon: "quadrant-test-brave", command: ["brave-origin", "%U"] },
        { id: "absolute-app", name: "Absolute App", icon: Quickshell.env("QUADRANT_ABSOLUTE_ICON"), command: ["absolute-app"] }
      ]
    }
    Components.ProcessList {
      id: first
      width: parent.width
      apps: apps
      rows: Model.nameAndCollapse([{ pid: 1, start: 1, comm: "t3code", exe: "t3code", value: 2 },
        { pid: 2, start: 2, comm: "brave", exe: "brave", value: 1 },
        { pid: 3, start: 3, comm: "absolute-app", value: 0.5 }], 10)
      expandable: true; expandedReady: true; expandedRows: rows
    }
    Components.ProcessList { id: second; apps: apps; active: false }
    Component { id: resolverComponent; Components.ProcessApps { } }
    Component { id: listComponent; Components.ProcessList { width: 400 } }
    QtObject {
      id: nativeBackend
      property var paths: ({})
      function iconSource(icon) { return paths[icon] || "" }
    }
    QtObject {
      id: nativeFacade
      property var callback: function(icon) { return nativeBackend.iconSource(icon) }
      function iconSource(icon) { return callback(icon) }
    }
    Process {
      id: installIcon
      command: ["cp", Quickshell.env("QUADRANT_ICON_TEMPLATE"), Quickshell.env("QUADRANT_LATE_ICON")]
    }
    FileView { id: requests; path: Quickshell.env("QUADRANT_ICON_REQUESTS"); printErrors: false }
    TestCase {
      name: "ProcessIcons"
      when: win.visible
      function cleanupTestCase() {
        console.log("QPROCESSICONS " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount }))
      }
      function cleanup() {
        if (qtest_results.failed) console.error("QPROCESSICONS failure: " + qtest_results.functionName)
      }
      function test_shared_launcher_retains_the_apps_desktop_identity() {
        var main = { id: "foot", name: "Foot", icon: Quickshell.env("QUADRANT_ICON_TEMPLATE"), command: ["foot"] }
        var server = { id: "foot-server", name: "Foot Server", icon: "foot", startupClass: "foot", command: ["foot", "--server"] }
        var resolver = createTemporaryObject(resolverComponent, win.contentItem, { desktopValues: [main] })
        verify(resolver)
        var rows = Model.nameAndCollapse([{ pid: 4, start: 4, comm: "foot", exe: "foot", value: 1 }], 1)
        var view = createTemporaryObject(listComponent, win.contentItem, { apps: resolver })
        verify(view)
        view.rows = rows
        for (var entries of [[server, main], [main, server]]) {
          resolver.desktopValues = entries
          compare(view.entryForRow(rows[0]).name, "Foot")
          tryVerify(function() {
            var image = findChild(view, "processIcon_0")
            return image && String(image.source) === resolver.fileUrl(Quickshell.env("QUADRANT_ICON_TEMPLATE")) && image.status === Image.Ready
          })
        }
      }
      function test_existing_delegate_refreshes_after_a_late_icon_install() {
        compare(first.appResolver, second.appResolver)
        wait(400)
        requests.reload(); wait(30)
        compare(requests.text(), "", "closed resolver performs no filesystem scan")
        var beforeRows = first.rows, beforeEntries = apps.desktopValues
        var image = findChild(first, "processIcon_0")
        verify(image)
        verify(String(image.source).indexOf("quadrant-test-t3") < 0, "the initial miss uses a fallback")
        apps.active = true
        tryVerify(function() { return !!apps.iconIndex["quadrant-test-brave"] }, 5000)
        compare(first.entryForRow(first.rows[1]).name, "Brave Origin")
        var braveImage = findChild(first, "processIcon_1")
        tryCompare(braveImage, "status", Image.Ready)
        installIcon.running = true
        tryCompare(installIcon, "running", false)
        apps.refreshIcons()
        tryVerify(function() { return String(image.source).indexOf("quadrant-test-t3.svg") >= 0 }, 5000)
        tryCompare(image, "status", Image.Ready)
        compare(findChild(first, "processIcon_0"), image, "refresh keeps the existing delegate")
        compare(first.rows, beforeRows)
        compare(apps.desktopValues, beforeEntries)
        first.expanded = true; first.query = "Origin"
        compare(first.displayRows.length, 1, "search follows the same desktop identity as the icon")
        requests.reload(); wait(30)
        var count = requests.text().trim().split("\n").length
        for (var i = 0; i < 10; i++) first.expandedRows = first.expandedRows.slice()
        wait(450); requests.reload(); wait(30)
        compare(requests.text().trim().split("\n").length, count, "process samples do not rescan icons")
        first.expanded = false
      }
      function test_native_callback_keeps_async_icon_index_dependencies() {
        // Same callback boundary as PluginAppLibraryApi; no appsChanged signal
        // accompanies the later file-index publication.
        apps.nativeAppLibrary = nativeFacade
        var image = findChild(first, "processIcon_0")
        nativeBackend.paths = ({})
        wait(30)
        var nativeUrl = apps.fileUrl(Quickshell.env("QUADRANT_ICON_TEMPLATE"))
        verify(String(image.source) !== nativeUrl)
        nativeBackend.paths = { "quadrant-test-t3": nativeUrl }
        tryCompare(image, "source", nativeUrl)
        tryCompare(image, "status", Image.Ready)
        apps.nativeAppLibrary = null
        tryCompare(image, "status", Image.Ready)
      }
      function test_missing_absolute_icon_retries_on_explicit_refresh() {
        var image = findChild(first, "processIcon_2")
        verify(image)
        tryCompare(image, "loadFailed", true)
        var primary = image.primarySource
        installIcon.command = ["cp", Quickshell.env("QUADRANT_ICON_TEMPLATE"), Quickshell.env("QUADRANT_ABSOLUTE_ICON")]
        installIcon.running = true
        tryCompare(installIcon, "running", false)
        apps.refreshIcons()
        tryCompare(image, "loadFailed", false)
        tryCompare(image, "status", Image.Ready)
        compare(image.primarySource, primary, "the file appears at the same URL")
        compare(String(image.source), primary)
        compare(findChild(first, "processIcon_2"), image)
      }
    }
  }
}
