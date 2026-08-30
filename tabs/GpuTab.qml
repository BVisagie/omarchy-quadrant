import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Theme.js" as Theme
import "../components" as Components

// GPU tab. AMD and Intel data ride the 1 Hz stream (sysfs); NVIDIA data
// comes from the widget's on-demand nvidia-smi sampler. Per-process GPU
// attribution is deliberately out of scope for v1 (fdinfo/compute-apps
// parsing lands behind a fixture-tested parser later).
Item {
  id: root

  property var panel: null
  property var model: null

  readonly property var gpu: model ? model.gpu : null
  readonly property string vendor: gpu ? gpu.vendor : ""
  // Unified live view: nvidia rows arrive via model.nvidiaGpu; amd/intel
  // via the stream sample's gpu object.
  readonly property var live: {
    if (!model) return null
    if (vendor === "nvidia") return model.nvidiaGpu
    return model.sample ? model.sample.gpu : null
  }
  readonly property string nvidiaError: model ? model.nvidiaError : ""

  implicitWidth: 200
  implicitHeight: column.implicitHeight

  function refresh() {
    // Stream-fed vendors need no panel sampler; NVIDIA polls from the
    // widget while this tab is open — nudge it for an immediate refresh.
    if (model && vendor === "nvidia" && model.pollNvidia) model.pollNvidia()
  }

  function busyText() {
    if (!live) return "--"
    if (vendor === "intel") {
      if (live.freqCurMhz !== null && live.freqMaxMhz !== null && live.freqMaxMhz > 0)
        return Model.formatPct(Model.clamp(100 * live.freqCurMhz / live.freqMaxMhz, 0, 100), 1)
      return "--"
    }
    var v = vendor === "nvidia" ? live.utilPct : live.busy
    return v === null ? "--" : Model.formatPct(v, 1)
  }

  function vramFraction() {
    if (!live) return 0
    var used = vendor === "nvidia" ? live.memUsedM : live.vramUsed
    var total = vendor === "nvidia" ? live.memTotalM : live.vramTotal
    if (used === null || total === null || total <= 0) return 0
    return Model.clamp(used / total, 0, 1)
  }

  function vramText() {
    if (!live) return "--"
    if (vendor === "nvidia") {
      if (live.memUsedM === null || live.memTotalM === null) return "--"
      return live.memUsedM + " of " + live.memTotalM + " MiB"
    }
    if (live.vramUsed === null || live.vramTotal === null) return "--"
    return Model.formatBytes(live.vramUsed) + " of " + Model.formatBytes(live.vramTotal)
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(8)

    // Multi-GPU selector — only when more than one card was detected.
    Row {
      visible: root.model && root.model.gpus.length > 1
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        text: "Card"
        color: root.panel ? Qt.darker(root.panel.barForeground, 1.4) : "#cacccc"
        font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Repeater {
        model: root.model ? root.model.gpus : []

        delegate: Rectangle {
          required property var modelData
          readonly property bool current: root.gpu && root.gpu.card === modelData.card
          width: cardLabel.implicitWidth + Style.space(12)
          height: cardLabel.implicitHeight + Style.space(6)
          radius: Style.cornerRadius
          color: current ? Style.selectedFillFor(root.panel ? root.panel.barForeground : "#cacccc", "#7aa2f7")
                         : Style.normalFillFor(root.panel ? root.panel.barForeground : "#cacccc", "#7aa2f7")

          Text {
            id: cardLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.card + " · " + modelData.vendor
            color: root.panel ? root.panel.barForeground : "#cacccc"
            font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.model) root.model.selectGpu(modelData.card)
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.nvidiaError !== ""
      text: root.nvidiaError
      color: "#f7768e"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      width: parent.width
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(18)
      visible: root.live !== null

      Components.RingGauge {
        // Intel has no busy percent without CAP_PERFMON; show the frequency
        // ratio and label it honestly.
        fraction: {
          if (!root.live) return 0
          if (root.vendor === "intel") {
            if (root.live.freqCurMhz !== null && root.live.freqMaxMhz !== null && root.live.freqMaxMhz > 0)
              return Model.clamp(root.live.freqCurMhz / root.live.freqMaxMhz, 0, 1)
            return 0
          }
          var v = root.vendor === "nvidia" ? root.live.utilPct : root.live.busy
          return v === null ? 0 : Model.clamp(v / 100, 0, 1)
        }
        color: Theme.series.gpu
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: root.busyText()
        subText: root.vendor === "intel" ? "freq" : "busy"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }

      Components.RingGauge {
        visible: root.vendor !== "intel"
        fraction: root.vramFraction()
        color: Theme.series.memCache
        trackColor: Theme.trackFor(root.panel ? root.panel.barForeground : "#cacccc")
        centerText: root.live && vramTotalKnown() ? Model.formatPct(root.vramFraction() * 100) : "--"
        subText: "VRAM"
        foreground: root.panel ? root.panel.barForeground : "#cacccc"
        fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Components.StatRow {
      width: parent.width
      label: "VRAM"
      visible: root.vendor !== "intel"
      value: root.vramText()
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Temperature"
      value: root.live ? Model.formatTemp(root.live.tempC) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: "Power"
      visible: root.vendor !== "intel"
      value: root.live && root.live.powerW !== null ? Model.formatWatts(root.live.powerW) : "--"
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Components.StatRow {
      width: parent.width
      label: root.vendor === "intel" ? "Frequency" : "Core clock"
      value: {
        if (!root.live) return "--"
        if (root.vendor === "intel")
          return Model.formatMhz(root.live.freqCurMhz) + " / " + Model.formatMhz(root.live.freqMaxMhz)
        return Model.formatMhz(root.live.clockMhz)
      }
      foreground: root.panel ? root.panel.barForeground : "#cacccc"
      fontFamily: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
    }

    Text {
      textFormat: Text.PlainText
      visible: root.vendor === "intel"
      text: "Intel busy % needs CAP_PERFMON; Quadrant shows the frequency ratio instead."
      color: root.panel ? Qt.darker(root.panel.barForeground, 1.5) : "#cacccc"
      font.family: root.panel && root.panel.bar ? root.panel.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }

  function vramTotalKnown() {
    if (!live) return false
    var total = vendor === "nvidia" ? live.memTotalM : live.vramTotal
    return total !== null && total > 0
  }
}
