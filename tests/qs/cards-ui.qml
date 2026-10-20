//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons as Commons
import "tabs" as Tabs
import "lib/index.mjs" as Model

// An isolated window keeps the layout sweep independent of the header,
// search and graph controls exercised by panel-ui.qml.
ShellRoot {
 Window {
  id: testWindow
  visible: true
  width: 752
  height: 1800
  Component { id: cpuComponent; Tabs.CpuTab { } }
  Component { id: gpuComponent; Tabs.GpuTab { } }
  Component { id: memoryComponent; Tabs.MemoryTab { } }
  Component { id: diskComponent; Tabs.DiskTab { } }
  Component { id: networkComponent; Tabs.NetworkTab { } }
  TestCase {
    id: testCase
    name: "ResourceCards"
    when: testWindow.visible
    windowShown: true
    function cleanupTestCase() {
      console.log("QPANELUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount }))
    }
    function cleanup() {
      if (qtest_results.failed) console.error("QPANELUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag)
    }
    function test_resource_cards_and_details_fit_data() {
      var cases = []
      for (var tab of ["cpu", "gpu", "mem", "disk", "net"])
        for (var width of [320, 720])
          for (var font of [12, 18]) cases.push({ tag: tab + " " + width + " " + font, tab: tab, width: width, font: font })
      return cases
    }
    function test_resource_cards_and_details_fit(data) {
      Commons.Style.applyShellValues({ "font.base-size": data.font })
      testWindow.width = data.width + 32
      var components = { cpu: cpuComponent, gpu: gpuComponent, mem: memoryComponent, disk: diskComponent, net: networkComponent }
      var props = { width: data.width, z: 1 }
      if (data.tab === "gpu") props.model = {
        gpu: { card: "card1", vendor: "intel", name: "Dedicated GPU" }, gpuLive: null, gpuDisplay: null,
        gpuRows: [], discreteGpus: [], nvidiaError: "", gpuHistory: [], gpuLong: [], cfg: Model.readSettings({}), barIntervalMs: 1000
      }
      var view = createTemporaryObject(components[data.tab], testWindow.contentItem, props)
      verify(view); wait(50)
      var roster = view.processList
      var button = findChild(view, "expandDetails")
      verify(button && button.enabled)
      function checkBounds(item) {
        if (!item.visible) return
        if (item.sectionCard === true || ("text" in item && typeof item.text === "string" && item.text !== "")) {
          var point = item.mapToItem(view, 0, 0)
          var fits = point.x >= -0.5 && point.x + item.width <= view.width + 0.5
          if (!fits) console.error("QPANELUI overflow: " + (item.title || item.text) + " x=" + point.x + " width=" + item.width + " tab=" + view.width)
          verify(fits, "content fits: " + (item.title || item.text))
        }
        for (var child of item.children) checkBounds(child)
      }
      checkBounds(view)
      mouseClick(button); wait(20)
      compare(button.text, "Collapse details")
      verify(Model.visibleDetails(view).every(function (item) { return item.expanded }))
      checkBounds(view)
      view.width = data.width === 720 ? 320 : 720
      testWindow.width = view.width + 32
      wait(20); checkBounds(view)
      compare(view.processList, roster, "cards retain the original process controls")
      mouseClick(button); wait(20)
      verify(Model.visibleDetails(view).every(function (item) { return !item.expanded }))
    }
  }
 }
}
