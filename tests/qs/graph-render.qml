//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons as Commons
import "components" as Components
import "lib/index.mjs" as Model
import "graph-data.mjs" as Fixture

ShellRoot {
  id: harness
  property string outPath: Quickshell.env("QUADRANT_RENDER_OUT")
  property string palette: Quickshell.env("QUADRANT_RENDER_PALETTE") || "dark"
  property string pattern: Quickshell.env("QUADRANT_RENDER_PATTERN") || "normal"
  property bool longer: Quickshell.env("QUADRANT_RENDER_LONG") === "1"
  property real cardWidth: Number(Quickshell.env("QUADRANT_RENDER_WIDTH")) || 440
  readonly property var pal: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent), String(Commons.Color.foreground), String(Commons.Color.background))
  readonly property var points: Fixture.history(longer, pattern)
  property bool showHover: Quickshell.env("QUADRANT_RENDER_HOVER") === "1"
  function fields(kind) {
    var keys = kind === "GPU" ? ["b", "v"] : kind === "Network" ? ["rx", "tx"] : ["r", "w"]
    var labels = kind === "GPU" ? ["busy", "VRAM"] : kind === "Network" ? ["down", "up"] : ["read", "write"]
    return [{ key: keys[0], label: labels[0], color: pal.primary }, { key: keys[1], label: labels[1], color: pal.secondary }]
  }
  function applyPalette() {
    Commons.Color.shellValues = ({})
    Commons.Color.background = palette === "light" ? "#faf6ef" : palette === "mono" ? "#000000" : "#081217"
    Commons.Color.foreground = palette === "light" ? "#3d3b50" : palette === "mono" ? "#eeeeee" : "#c8d8de"
    Commons.Color.accent = palette === "light" ? "#5850a0" : palette === "mono" ? "#cccccc" : "#70b7be"
    Commons.Color.urgent = palette === "mono" ? "#ffffff" : "#b34b4b"
  }
  Window {
    id: win
    visible: true
    width: harness.cardWidth * 2 + 16
    height: Math.ceil(content.implicitHeight)
    color: Commons.Color.background
    Rectangle { anchors.fill: parent; color: Commons.Color.background }
    Column {
      id: content
      width: parent.width
      spacing: 16
      Text {
        x: 16; width: parent.width - 32
        textFormat: Text.PlainText
        text: "Graph layouts · " + harness.palette + " · " + harness.cardWidth + " px · " + (harness.longer ? "1 hour" : "1 min") + " · " + harness.pattern + "\nSynthetic data; paired charts use identical measurements and time."
        color: Commons.Color.foreground
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        wrapMode: Text.WordWrap
      }
      Repeater {
        model: ["GPU", "Network", "Drives"]
        delegate: Item {
          id: pair
          required property string modelData
          width: content.width
          implicitHeight: Math.max(left.implicitHeight, right.implicitHeight) + 32
          Rectangle { width: harness.cardWidth; height: parent.height; color: "transparent"; border.color: harness.pal.grid }
          Rectangle { x: harness.cardWidth + 16; width: harness.cardWidth; height: parent.height; color: "transparent"; border.color: harness.pal.grid }
          Components.GraphBlock {
            id: left
            x: 16; y: 16
            width: harness.cardWidth - 32
            title: pair.modelData + " · OVERLAY"
            finePoints: harness.points
            longPoints: harness.points
            longWindow: harness.longer
            fields: harness.fields(pair.modelData)
            fixedMax: pair.modelData === "GPU" ? 100 : 0
            minimumMax: pair.modelData === "GPU" ? 0 : 1024
            formatValue: function (v) { return pair.modelData === "GPU" ? Model.formatPct(v) : Model.formatRate(v) }
            hoverFraction: harness.showHover ? 0.7 : -1
            legend: fields.map(function (field) {
              var value = Model.graphValue(harness.points[harness.points.length - 1], field.key)
              return { label: field.label, color: field.color, value: value === null ? "--" : formatValue(value) }
            })
          }
          Components.GraphBlock {
            id: right
            x: harness.cardWidth + 32; y: 16
            width: left.width
            title: pair.modelData + (pair.modelData === "GPU" ? " · ALIGNED" : " · MIRRORED")
            graphLayout: pair.modelData === "GPU" ? "aligned" : "mirrored"
            finePoints: harness.points
            longPoints: harness.points
            longWindow: harness.longer
            fields: harness.fields(pair.modelData)
            fixedMax: left.fixedMax
            minimumMax: left.minimumMax
            formatValue: left.formatValue
            legend: left.legend
            hoverFraction: harness.showHover ? 0.7 : -1
          }
          Component.onCompleted: Qt.callLater(function () {
            console.log("GRAPH_HEIGHT " + JSON.stringify({ resource: pair.modelData, overlay: left.implicitHeight, alternative: right.implicitHeight, width: left.width }))
          })
        }
      }
    }
  }
  Timer {
    interval: 300
    repeat: true
    running: true
    property bool ready: false
    onTriggered: {
      if (!ready) { harness.applyPalette(); ready = true; return }
      stop()
      win.contentItem.grabToImage(function (result) {
        result.saveToFile(harness.outPath)
        console.log("RENDER saved " + harness.outPath)
        Qt.quit()
      })
    }
  }
}
