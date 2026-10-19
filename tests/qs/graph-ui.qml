//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons as Commons
import "components" as Components
import "tabs" as Tabs
import "lib/index.mjs" as Model
import "graph-data.mjs" as Fixture

ShellRoot {
 Window {
  id: win
  width: 440
  height: 1500
  visible: true
  Components.GraphBlock {
    id: graph
    x: 16; y: 16
    width: win.width - 32
    title: "HISTORY"
    fields: [{ key: "b", label: "busy", color: "#70b7be" }, { key: "v", label: "VRAM", color: "#9070be" }]
    fixedMax: 100
    finePoints: Fixture.history(false, "normal")
    longPoints: Fixture.history(true, "normal")
    onToggleWindow: longWindow = !longWindow
  }
  QtObject {
    id: settingsStore
    property var cfg: Model.readSettings({})
    property var lastPatch: ({})
    property var sample: null
    property var gpus: []
    property var discreteGpus: []
    property bool discreteGpuAvailable: false
    property var diskInfo: null
    function persistSettings(patch) { lastPatch = patch; cfg = Model.readSettings(Model.settingsPatch(cfg, patch)) }
  }
  Component { id: settingsComponent; Components.SettingsView { } }
  Component { id: gpuComponent; Tabs.GpuTab { } }
  Component { id: storeComponent; Components.Store { } }
  Component { id: networkComponent; Tabs.NetworkTab { } }
  Component { id: diskComponent; Tabs.DiskTab { } }
  TestCase {
    name: "GraphLayouts"
    when: win.visible
    windowShown: true
    property var initialStyle: ({})
    function initTestCase() { wait(20); initialStyle = Object.assign({}, Commons.Color.shellValues) }
    function cleanupTestCase() { console.log("QGRAPHUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount })) }
    function cleanup() {
      if (qtest_results.failed) console.error("QGRAPHUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag)
    }
    function init() {
      Commons.Style.applyShellValues(initialStyle)
      graph.graphLayout = "overlay"; graph.longWindow = false; graph.hoverFraction = -1
      graph.finePoints = Fixture.history(false, "normal"); graph.longPoints = Fixture.history(true, "normal")
      graph.fixedMax = 100; graph.minimumMax = 0
      graph.fields = [{ key: "b", label: "busy", color: "#70b7be" }, { key: "v", label: "VRAM", color: "#9070be" }]
      graph.formatValue = function (v) { return Model.formatPct(v) }
      graph.sampleSeconds = 1
      win.width = 440
      settingsStore.cfg = Model.readSettings({}); settingsStore.lastPatch = ({})
      wait(20)
    }
    function plot(index) { return findChild(graph, index ? "historyPlot_" + index : "historyPlot") }
    function xAt(time, view) {
      return (time - graph.points[graph.points.length - 1].t + graph.windowSeconds) / graph.windowSeconds * (view.plotWidth - 1)
    }
    function test_aligned_shares_time_scale_hover_and_duration() {
      graph.graphLayout = "aligned"
      wait(20)
      var first = plot(0), second = plot(1)
      verify(first && second)
      compare(first.axis.min, 0); compare(second.axis.min, 0)
      compare(first.axis.max, 100); compare(second.axis.max, 100)
      compare(first.plotWidth, second.plotWidth)
      compare(first.points, second.points)
      mouseMove(first, first.plotWidth * 0.8, first.height / 2)
      tryVerify(function () { return first.hoverInfo !== null })
      compare(first.hoverIndex, second.hoverIndex)
      compare(first.hoverInfo.t, second.hoverInfo.t)
      verify(first.hoverText.indexOf("busy ") >= 0 && second.hoverText.indexOf("VRAM ") >= 0)
      mouseMove(second, second.plotWidth * 0.6, second.height / 2)
      compare(first.hoverIndex, second.hoverIndex)
      mouseWheel(second, second.plotWidth / 2, second.height / 2, 0, 120)
      verify(graph.longWindow)
      compare(first.windowSeconds, 3600); compare(second.windowSeconds, 3600)
      compare(findChild(graph, "graphBucketLabel").text, "10 s means")
      mouseClick(findChild(graph, "graphMinute"))
      verify(!graph.longWindow)
      mouseClick(findChild(graph, "graphSeriesSummary_1"))
      verify(graph.longWindow, "aligned summaries keep the shared window shortcut")
    }
    function test_mirror_keeps_positive_rates_and_names_both_directions() {
      graph.fixedMax = 0; graph.minimumMax = 1024
      graph.fields = [{ key: "rx", label: "down", color: "#70b7be" }, { key: "tx", label: "up", color: "#9070be" }]
      graph.formatValue = function (v) { return Model.formatRateUnit(v, "bits") }
      var summary = graph.note, max = plot(0).axis.max, height = graph.implicitHeight
      graph.graphLayout = "mirrored"
      wait(20)
      var view = plot(0)
      verify(view.mirrored)
      compare(graph.note, summary)
      compare(view.axis.max, max)
      verify(graph.implicitHeight > height)
      verify(findChild(view, "axisTop").text.indexOf("down\n") === 0)
      verify(findChild(view, "axisBottom").text.indexOf("up\n") === 0)
      mouseMove(view, view.plotWidth * 0.75, view.height * 0.75)
      tryVerify(function () { return view.hoverInfo !== null })
      verify(view.hoverText.indexOf("down ") >= 0 && view.hoverText.indexOf("up ") >= 0)
      verify(view.hoverText.indexOf("-") < 0)
      verify(view.hoverText.indexOf(Model.formatRateUnit(view.hoverInfo.rx, "bits")) >= 0)
      verify(view.hoverText.indexOf(Model.formatRateUnit(view.hoverInfo.tx, "bits")) >= 0)
    }
    function test_null_gap_low_activity_and_stale_timestamp_data() {
      return [ { tag: "overlay", layout: "overlay" }, { tag: "aligned", layout: "aligned" }, { tag: "mirrored", layout: "mirrored" } ]
    }
    function test_null_gap_low_activity_and_stale_timestamp(data) {
      graph.graphLayout = data.layout
      graph.finePoints = [{ t: 1, b: 0, v: 10 }, { t: 2, b: null, v: 20 }, { t: 3, b: 0.1, v: 30 }, { t: 60, b: 0.2, v: 40 }]
      wait(20)
      var view = plot(0)
      compare(view.valueOf(graph.points[1], "b"), null)
      compare(view.valueOf(graph.points[0], "b"), 0)
      compare(view.axis.max, 100)
      compare(view.indexAtX(xAt(30, view), view.plotWidth), -1, "blank time gap has no old readout")
      graph.hoverFraction = xAt(2, view) / (view.plotWidth - 1)
      compare(view.hoverInfo.t, 2)
      verify(view.hoverText.indexOf("busy --") >= 0)
      compare(findChild(graph, "graphEndTime").text, Qt.formatTime(new Date(60000), "hh:mm:ss"))
      verify(findChild(graph, "graphEndTime").text !== "now", "stale history prints its actual end time")
      graph.fixedMax = 0; graph.minimumMax = 1024
      compare(view.axis.min, 0); compare(view.axis.max, 1024)
    }
    function test_summaries_follow_visible_window_and_name_unknown_series() {
      graph.finePoints = [{ t: 1, b: 100, v: 100 }, { t: 50, b: 20, v: null }, { t: 100, b: 40, v: null }]
      compare(graph.points.length, 2)
      compare(graph.stats.avg, 30)
      verify(graph.note.indexOf("busy · avg 30% · peak 40%") === 0)
      verify(graph.note.indexOf("VRAM · avg -- · peak --") > 0)
      graph.graphLayout = "aligned"
      wait(20)
      compare(plot(0).points.length, 2)
      compare(plot(1).points.length, 2)
      verify(plot(1).hoverText === "")
      graph.longPoints = [{ t: 100, b: 10, v: 80 }, { t: 110, b: 30, v: 60 }]
      graph.longWindow = true
      compare(graph.stats.avg, 20); compare(graph.stats.peak, 30)
      compare(findChild(graph, "graphBucketLabel").text, "10 s means")
    }
    function test_widths_and_styles_data() {
      var cases = []
      for (var width of [320, 440]) for (var layout of ["overlay", "aligned", "mirrored"])
        for (var scale of [1, 1.5, 2]) cases.push({ tag: width + " " + layout + " " + scale, width: width, layout: layout, scale: scale })
      return cases
    }
    function test_widths_and_styles(data) {
      win.width = data.width
      Commons.Style.applyShellValues({ "font.base-size": 18, "spacing.scale": data.scale })
      graph.graphLayout = data.layout
      wait(20)
      var view = plot(0)
      verify(view.plotWidth > 80)
      var axis = findChild(view, "axisTop")
      verify(axis.x >= view.plotWidth && axis.x + axis.width <= view.width + 0.5)
      var duration = findChild(graph, "graphDuration")
      verify(duration.x >= 0)
      var timeAxis = findChild(graph, "graphTimeAxis")
      compare(timeAxis.width, view.plotWidth)
      graph.longWindow = true
      wait(20)
      var bucket = findChild(graph, "graphBucketLabel"), end = findChild(graph, "graphEndTime")
      verify(bucket.x > 0 && bucket.x + bucket.width <= end.x, "time and bucket captions fit")
      mouseMove(view, view.plotWidth * 0.7, view.height / 2)
      wait(10)
      var readout = findChild(view, "graphReadout")
      verify(readout.width <= view.plotWidth)
      if (data.layout === "aligned") compare(view.plotWidth, plot(1).plotWidth)
    }
    function test_real_store_settings_reach_all_three_tabs() {
      var store = createTemporaryObject(storeComponent, this, { settingsRaw: {}, saveIntervalMs: 60000 })
      verify(store)
      var gpu = createTemporaryObject(gpuComponent, win.contentItem, { width: 408, model: store })
      var network = createTemporaryObject(networkComponent, win.contentItem, { width: 408, model: store })
      var disk = createTemporaryObject(diskComponent, win.contentItem, { width: 408, model: store })
      verify(gpu && network && disk)
      store.applySettings({ gpuGraphLayout: '"aligned"', networkGraphLayout: "mirrored", diskGraphLayout: "overlay" })
      wait(20)
      compare(findChild(gpu, "gpuHistory").graphLayout, "aligned")
      compare(findChild(network, "networkHistory").graphLayout, "mirrored")
      compare(findChild(disk, "diskHistory").graphLayout, "overlay")
      compare(findChild(network, "networkHistory").minimumMax, 1024)
      compare(findChild(disk, "diskHistory").minimumMax, 1024)
      store.applySettings({ diskGraphLayout: "mirrored" })
      wait(20)
      compare(findChild(gpu, "gpuHistory").graphLayout, "overlay")
      compare(findChild(network, "networkHistory").graphLayout, "overlay")
      compare(findChild(disk, "diskHistory").graphLayout, "mirrored")
    }
    function test_settings_controls_persist_independently_without_hardware() {
      var settings = createTemporaryObject(settingsComponent, win.contentItem, { width: 408, store: settingsStore })
      verify(settings)
      wait(20)
      for (var resource of ["gpu", "network", "disk"]) {
        var control = findChild(settings, resource + "GraphLayoutChoice")
        verify(control.visible)
        control.open()
        wait(20)
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
        tryCompare(control, "popupOpen", false)
        compare(settingsStore.lastPatch[resource + "GraphLayout"], resource === "gpu" ? "aligned" : "mirrored")
        compare(control.value, settingsStore.lastPatch[resource + "GraphLayout"])
      }
      compare(settingsStore.cfg.gpuGraphLayout, "aligned")
      compare(settingsStore.cfg.networkGraphLayout, "mirrored")
      compare(settingsStore.cfg.diskGraphLayout, "mirrored")
      // The control lives below the viewport in some font fixtures. Invoke
      // the same button action without relying on a synthetic offscreen click.
      findChild(settings, "resetSettings").clicked()
      compare(settingsStore.cfg.gpuGraphLayout, "overlay")
      compare(settingsStore.cfg.networkGraphLayout, "overlay")
      compare(settingsStore.cfg.diskGraphLayout, "overlay")
    }
  }
 }
}
