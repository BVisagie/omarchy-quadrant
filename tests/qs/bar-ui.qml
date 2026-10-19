//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons as Commons
import "." as Plugin
import "components" as Components
import "lib/index.mjs" as Model

ShellRoot {
 Window {
  id: win
  visible: true
  width: 1400
  height: 1600
  BarFixture { id: shared }
  BarHost { id: host; service: shared; widgets: [first, second] }
  Plugin.BarWidget { id: first; objectName: "first"; x: 16; y: 16; width: implicitWidth; height: implicitHeight; bar: host; settings: shared.settingsRaw }
  Plugin.BarWidget { id: second; objectName: "second"; x: 16; y: 400; width: implicitWidth; height: implicitHeight; bar: host; settings: shared.settingsRaw }
  Component { id: settingsComponent; Components.SettingsView { } }
  Component { id: realStoreComponent; Components.Store { } }
  TestCase {
    name: "BarTrendsAndOrder"
    when: win.visible
    windowShown: true
    property var initialStyle: ({})
    function initTestCase() { wait(30); initialStyle = Object.assign({}, Commons.Color.shellValues) }
    function cleanupTestCase() { console.log("QBARUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount })) }
    function cleanup() { if (qtest_results.failed) console.error("QBARUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag) }
    function init() {
      Commons.Style.applyShellValues(initialStyle)
      host.vertical = false; host.barSize = 26
      shared.gpuTopologyReady = true; shared.gpuListFailed = false
      shared.discreteGpuAvailable = true; shared.diskAvailable = true
      shared.gpu = { vendor: "intel" }; shared.streamLive = true
      shared.applySettings({ segments: Model.BAR_SEGMENTS })
      shared.cpuPct = { nonIdle: 42 }; shared.memComp = { usedPct: 62 }
      shared.gpuDisplay = { pct: 38, estimated: false }; shared.diskRates = { utilPct: 18 }
      shared.ifaceRates = { rxBps: 1024, txBps: 20 }
      shared.seed(1000)
      first.close(); second.close()
      wait(200)
    }
    function cell(widget, metric) { return findChild(widget, "barCell_" + metric) }
    function trend(widget, metric) { return findChild(cell(widget, metric), "barTrend") }
    function assertFits(item) {
      if (item.implicitWidth > item.width + 0.5 || item.implicitHeight > item.height + 0.5)
        console.error("QBARUI fit " + JSON.stringify({ text: item.text, natural: [item.implicitWidth, item.implicitHeight], slot: [item.width, item.height], font: item.font.pixelSize }))
      verify(item.implicitWidth <= item.width + 0.5, "full value fits: " + item.text)
      verify(item.implicitHeight <= item.height + 0.5, "value fits vertically: " + item.text)
    }
    function test_service_shared_by_monitors_and_no_embedded_fallback() {
      compare(first.store, shared); compare(second.store, shared)
      compare(first.storeTries, 0); compare(second.storeTries, 0)
      compare(Object.keys(shared.viewers).length, 2)
      verify(!trend(first, "cpu"), "default text has no graph object")
      shared.persistSettings({ barStyle: "graph-text" })
      wait(30)
      for (var metric of ["cpu", "gpu", "mem", "disk", "net"]) {
        verify(trend(first, metric) && trend(second, metric))
        compare(trend(first, metric).points, trend(second, metric).points)
      }
      compare(trend(first, "cpu").points, shared.cpuHistory)
      compare(trend(first, "disk").samples[0].v, shared.diskHistory[0].b)
      compare(trend(first, "cpu").axis.max, 100)
      compare(trend(first, "net").keys.length, 2)
      shared.pulse(1001)
      wait(20)
      compare(trend(first, "cpu").samples[trend(first, "cpu").samples.length - 1].v,
        trend(second, "cpu").samples[trend(second, "cpu").samples.length - 1].v)
      compare(Object.keys(shared.viewers).length, 2)
      compare(first.storeTries, 0); compare(second.storeTries, 0)
      shared.persistSettings({ barStyle: "text" })
      wait(20)
      verify(!trend(first, "cpu") && !trend(second, "cpu"))
    }
    function test_order_fallback_and_click_registration() {
      var order = ["network", "disk", "gpu", "cpu", "memory"]
      shared.persistSettings({ barOrder: order, barStyle: "graph-text" })
      wait(200)
      var metrics = ["net", "disk", "gpu", "cpu", "mem"]
      for (var i = 0; i < metrics.length; i++) {
        verify(host.targets.indexOf(cell(first, metrics[i])) >= 0)
        if (i) verify(cell(first, metrics[i]).x > cell(first, metrics[i - 1]).x)
      }
      var removed = cell(first, "gpu")
      shared.discreteGpuAvailable = false
      wait(200)
      verify(!cell(first, "gpu")); verify(host.targets.indexOf(removed) < 0)
      compare(first.visibleBarCells.join(","), "net,disk,cpu,mem")
      compare(shared.cfg.barOrder.join(","), order.join(","))
      shared.diskAvailable = false; wait(200)
      verify(!cell(first, "disk"))
      shared.discreteGpuAvailable = true; shared.diskAvailable = true; wait(200)
      compare(first.visibleBarCells.join(","), "net,disk,gpu,cpu,mem")
      cell(first, "net").triggerPress(Qt.LeftButton)
      verify(first.opened)
      compare(first.viewerState.netTab, true)
      verify(!second.opened)
      cell(first, "disk").triggerPress(Qt.MiddleButton)
      compare(first.viewerState.diskTab, true)
      cell(first, "disk").triggerPress(Qt.LeftButton)
      verify(!first.opened)
      var ownTargets = host.targets.filter(function (target) { return target && target.objectName && target.objectName.indexOf("barCell_") === 0 })
      compare(ownTargets.length, 10)
      compare(new Set(ownTargets).size, 10, "no stale or duplicate click targets remain after reordering")
    }
    function test_trend_scale_tooltips_and_offline_state() {
      shared.persistSettings({ barStyle: "graph-text" })
      shared.netHistory = [{ t: 940, rx: 0, tx: 0 }, { t: 1000, rx: null, tx: 0 }]
      wait(20)
      compare(trend(first, "net").axis.max, 1024)
      verify(first.tooltipFor("net").indexOf("Minute trend: down / up · 0–1 KiB/s") >= 0)
      shared.persistSettings({ rateUnit: "bits" })
      verify(first.tooltipFor("net").indexOf("0–8.2 kb/s") >= 0)
      verify(first.tooltipFor("disk").indexOf("Minute trend: 0–100%") >= 0)
      shared.netHistory = [{ t: 1000, rx: 10000, tx: 40000 }]
      wait(20)
      verify(trend(first, "net").axis.max >= 40000, "both directions set the shared ceiling")
      shared.streamLive = false
      compare(first.tooltipFor("net"), "Quadrant: sampler offline")
      verify(trend(first, "net").samples.length > 0, "offline state does not invent or clear history")
      shared.streamLive = true
    }
    function test_widths_do_not_follow_values_data() {
      var cases = []
      for (var vertical of [false, true]) for (var style of ["text", "graph-text"])
        for (var labels of ["glyph", "letter", "none"]) for (var scale of [1, 1.5, 2])
          cases.push({ tag: [vertical, style, labels, scale].join(" "), vertical: vertical, style: style, labels: labels, scale: scale })
      return cases
    }
    function test_widths_do_not_follow_values(data) {
      Commons.Style.applyShellValues({ "font.base-size": 18, "spacing.scale": data.scale })
      host.vertical = data.vertical; host.barSize = Commons.Style.space(data.vertical ? 26 : 32)
      shared.persistSettings({ barStyle: data.style, barLabels: data.labels, barGraphWidth: 64 })
      wait(200)
      var width = first.implicitWidth, height = first.implicitHeight
      var positions = first.visibleBarCells.map(function (metric) { var item = cell(first, metric); return { x: item.x, y: item.y } })
      for (var value of [null, 0, 9, 99, 100]) {
        shared.cpuPct = value === null ? null : { nonIdle: value }
        shared.memComp = value === null ? null : { usedPct: value }
        shared.gpuDisplay = value === null ? null : { pct: value, estimated: true }
        shared.diskRates = value === null ? null : { utilPct: value }
        shared.ifaceRates = value === null ? null : { rxBps: value === 99 ? Number.MAX_VALUE : (value || 0) * 1023 * 1024 ** 4, txBps: (value || 0) * 1024 }
        wait(5)
        if (first.implicitWidth !== width || first.implicitHeight !== height)
          console.error("QBARUI slot moved " + JSON.stringify({ value: value, before: [width,height], after: [first.implicitWidth,first.implicitHeight] }))
        compare(first.implicitWidth, width); compare(first.implicitHeight, height)
        for (var i = 0; i < first.visibleBarCells.length; i++) {
          var metric = first.visibleBarCells[i], item = cell(first, metric)
          if (Math.abs(item.x-positions[i].x)>0.5 || Math.abs(item.y-positions[i].y)>0.5)
            console.error("QBARUI cell moved " + JSON.stringify({ metric: metric, value: value, before: positions[i], after: [item.x,item.y] }))
          fuzzyCompare(item.x, positions[i].x, 0.5); fuzzyCompare(item.y, positions[i].y, 0.5)
          var readings = metric === "net" ? [findChild(item, "barDown"), findChild(item, "barUp")] : [findChild(item, "barValue")]
          for (var reading of readings) {
            assertFits(reading)
            compare(reading.horizontalAlignment, data.vertical ? Text.AlignHCenter : Text.AlignLeft,
              "values stay beside their own label/trend, with slack after the reading")
          }
          if (data.vertical) verify(item.width <= host.barSize)
          if (data.style === "graph-text") verify(trend(first, metric).width <= (data.vertical ? host.barSize : Commons.Style.space(64)))
        }
      }
    }
    function test_gpu_vendor_reservation_and_uniform_vertical_percentages_data() {
      var cases = []
      for (var style of ["text", "graph-text"]) for (var vertical of [false, true])
        cases.push({ tag: style + " " + vertical, style: style, vertical: vertical })
      return cases
    }
    function test_gpu_vendor_reservation_and_uniform_vertical_percentages(data) {
      host.vertical = data.vertical
      shared.persistSettings({ barStyle: data.style })
      for (var size of [{ strip: 26, base: 12 }, { strip: 28, base: 12 }, { strip: 34, base: 16 }]) {
        Commons.Style.applyShellValues({ "font.base-size": size.base })
        host.barSize = size.strip
        var dedicatedWidth = null
        for (var vendor of ["amd", "nvidia", "intel"]) {
          shared.gpu = { vendor: vendor }
          shared.gpuDisplay = { pct: 100, estimated: false }
          wait(vendor === "amd" || (!data.vertical && vendor === "intel") ? 200 : 20)
          var gpuValue = findChild(cell(first, "gpu"), "barValue")
          var cpuValue = findChild(cell(first, "cpu"), "barValue")
          if (data.vertical) {
            for (var metric of ["cpu", "mem", "disk"])
              compare(findChild(cell(first, metric), "barValue").font.pixelSize, gpuValue.font.pixelSize,
                "visible percentage cells use one font size")
            if (vendor !== "intel") compare(gpuValue.font.pixelSize, Commons.Style.font.caption,
              "AMD/NVIDIA do not shrink to reserve an unavailable estimate prefix")
          } else if (vendor !== "intel") {
            compare(gpuValue.width, cpuValue.width, "only Intel needs a wider percentage slot")
            if (dedicatedWidth === null) dedicatedWidth = first.implicitWidth
            else compare(first.implicitWidth, dedicatedWidth)
          } else verify(gpuValue.width > cpuValue.width)
          var width = first.implicitWidth, fontSize = gpuValue.font.pixelSize
          var positions = first.visibleBarCells.map(function (metric) {
            var item = cell(first, metric); return { x: item.x, y: item.y }
          })
          for (var pct of [null, 9, 99, 100]) {
            for (var estimated of vendor === "intel" ? [false, true] : [false]) {
              shared.gpuDisplay = pct === null ? null : { pct: pct, estimated: estimated }
              wait(5)
              compare(first.implicitWidth, width); compare(gpuValue.font.pixelSize, fontSize)
              assertFits(gpuValue)
              for (var i = 0; i < first.visibleBarCells.length; i++) {
                var item = cell(first, first.visibleBarCells[i])
                fuzzyCompare(item.x, positions[i].x, 0.5); fuzzyCompare(item.y, positions[i].y, 0.5)
              }
            }
          }
        }
        // Intel remains selected, but a disabled GPU must not reduce the
        // remaining percentages to make room for its estimate prefix.
        shared.persistSettings({ segments: ["cpu", "memory", "disk", "network"] })
        wait(20)
        compare(findChild(cell(first, "cpu"), "barValue").font.pixelSize, Commons.Style.font.caption)
        shared.persistSettings({ segments: Model.BAR_SEGMENTS })
        wait(20)
      }
    }
    function test_icon_only_and_hardware_return_keep_order() {
      var order = ["network", "gpu", "memory", "disk", "cpu"]
      shared.persistSettings({ segments: [], barStyle: "graph-text", barOrder: order })
      wait(200)
      verify(first.showMonitorFallback && second.showMonitorFallback)
      compare(first.visibleBarCells.length, 0)
      verify(!findChild(first, "barTrend"))
      compare(host.targets.filter(function (target) { return target && target.objectName && target.objectName.indexOf("barCell_") === 0 }).length, 0)
      shared.discreteGpuAvailable = false; shared.diskAvailable = false
      shared.persistSettings({ segments: ["gpu"] })
      wait(200)
      verify(first.showMonitorFallback)
      shared.diskAvailable = true
      wait(200)
      compare(first.visibleBarCells.join(","), "disk")
      verify(trend(first, "disk"))
      shared.discreteGpuAvailable = true
      wait(200)
      compare(first.visibleBarCells.join(","), "gpu")
      compare(shared.cfg.barOrder.join(","), order.join(","))
    }
    function test_settings_moves_toggles_and_reset() {
      var settings = createTemporaryObject(settingsComponent, win.contentItem, { x: 650, width: 288, store: shared })
      verify(settings); wait(20)
      mouseClick(findChild(settings, "moveEarlier_network"))
      wait(20)
      compare(shared.cfg.barOrder.join(","), "cpu,gpu,memory,network,disk")
      var up = findChild(settings, "moveEarlier_network")
      up.forceActiveFocus(); keyClick(Qt.Key_Return); wait(20)
      compare(shared.cfg.barOrder.join(","), "cpu,gpu,network,memory,disk")
      verify(findChild(settings, "moveEarlier_network").activeFocus)
      mouseClick(findChild(settings, "segmentSwitch_network")); wait(20)
      verify(shared.cfg.segments.indexOf("network") < 0)
      mouseClick(findChild(settings, "segmentSwitch_network")); wait(20)
      verify(shared.cfg.segments.indexOf("network") >= 0)
      compare(shared.cfg.barOrder.indexOf("network"), 2)
      shared.discreteGpuAvailable = false
      verify(findChild(settings, "moveEarlier_gpu").visible)
      var choice = findChild(settings, "barStyleChoice")
      choice.open(); wait(20); keyClick(Qt.Key_Down); keyClick(Qt.Key_Return); wait(20)
      compare(shared.cfg.barStyle, "graph-text")
      verify(findChild(settings, "barGraphWidthChoice").visible)
      findChild(settings, "resetSettings").clicked(); wait(20)
      compare(shared.cfg.barStyle, "text"); compare(shared.cfg.barGraphWidth, 32)
      compare(shared.cfg.barOrder.join(","), Model.BAR_SEGMENTS.join(","))
    }
    function test_settings_drives_switch_controls_the_fallback() {
      shared.applySettings({ segments: Model.DEFAULT_BAR_SEGMENTS })
      shared.discreteGpuAvailable = false
      var settings = createTemporaryObject(settingsComponent, win.contentItem, { x: 650, width: 288, store: shared })
      verify(settings); wait(20)
      var drives = findChild(settings, "segmentSwitch_disk")
      verify(drives.checked, "the effective fallback is reflected by its switch")
      verify(findChild(settings, "segmentSwitch_gpu").checked, "missing GPU keeps its configured intent")
      mouseClick(drives); wait(20)
      verify(!shared.cfg.diskFallbackWithoutGpu && !shared.segmentEnabled("disk"))
      mouseClick(drives); wait(20)
      verify(shared.cfg.diskFallbackWithoutGpu && shared.segmentEnabled("disk"))
      shared.persistSettings({ segments: ["cpu"] }); wait(20)
      verify(!drives.checked)
      mouseClick(drives); wait(20)
      verify(shared.cfg.segments.indexOf("disk") >= 0, "without a GPU token Drives enables explicitly")
    }
    function test_real_store_persistence_and_drives_without_gpu_token() {
      var store = createTemporaryObject(realStoreComponent, this, { settingsRaw: { segments: ["cpu"], barOrder: ["network", "disk", "cpu"] } })
      verify(store)
      // createObject initial properties use QVariantList, as host APIs can.
      compare(store.cfg.segments.join(","), "cpu")
      compare(store.cfg.barOrder.join(","), "network,disk,cpu,gpu,memory")
      store.gpuTopologyReady = true; store.gpuListFailed = false; store.setGpu(null)
      var order = store.cfg.barOrder.join(",")
      store.setBarSegment("disk", true)
      verify(store.cfg.segments.indexOf("disk") >= 0)
      compare(store.cfg.barOrder.join(","), order)
      store.persistSettings({ barStyle: "graph-text", barGraphWidth: 48 })
      compare(store.cfg.barStyle, "graph-text"); compare(store.cfg.barGraphWidth, 48)
      var saved = Model.settingsPatch(store.settingsRaw, store.pendingSettings)
      store.applySettings(JSON.parse(JSON.stringify(saved)))
      compare(store.cfg.barStyle, "graph-text"); compare(store.cfg.barOrder.join(","), order)
      store.setBarSegment("disk", false)
      verify(store.cfg.segments.indexOf("disk") < 0)
      compare(store.cfg.diskFallbackWithoutGpu, false)
    }
  }
 }
}
