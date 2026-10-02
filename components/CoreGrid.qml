import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// Per-core load as a grid of cells: one cell per physical core (SMT
// siblings collapsed), rows per core class on hybrid chips. Cell colour
// is the theme heat ramp, so a busy core warms from muted through accent
// to urgent instead of flipping at a threshold.
//   layout — Model.coreGridLayout(topo, usageById)
Item {
  id: root

  property var layout: ({ mode: "uniform", rows: [] })
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var pal: Model.seriesPalette(String(Color.accent), String(Color.urgent), String(foreground), String(Color.background))
  readonly property bool hasCells: {
    var rows = root.layout && root.layout.rows ? root.layout.rows : []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].cells && rows[i].cells.length) return true
    }
    return false
  }

  visible: hasCells
  implicitWidth: 200
  implicitHeight: visible ? column.implicitHeight : 0

  function cellSize(kind) {
    if (kind === "performance") return Style.space(12)
    if (kind === "same") return Style.space(10)
    return Style.space(8)
  }

  function kindLabel(kind) {
    if (kind === "performance") return "P"
    if (kind === "efficiency") return "E"
    if (kind === "lowpower") return "LP"
    return ""
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      text: "CORES"
      color: root.pal.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Repeater {
      model: root.layout && root.layout.rows ? root.layout.rows : []

      delegate: Item {
        id: rowRoot
        required property var modelData
        width: column.width
        implicitHeight: Math.max(kindText.implicitHeight, flow.implicitHeight)

        Text {
          id: kindText
          textFormat: Text.PlainText
          visible: root.layout && root.layout.mode === "hybrid" && root.kindLabel(rowRoot.modelData.kind) !== ""
          text: root.kindLabel(rowRoot.modelData.kind)
          color: root.pal.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: visible ? Style.space(18) : 0
          horizontalAlignment: Text.AlignRight
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Flow {
          id: flow
          anchors.left: kindText.right
          anchors.leftMargin: kindText.visible ? Style.space(6) : 0
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)

          Repeater {
            model: rowRoot.modelData.cells || []
            delegate: Rectangle {
              id: cell
              required property var modelData
              readonly property real usage: Math.max(0, Math.min(100, Number(modelData.usage) || 0))
              width: root.cellSize(rowRoot.modelData.kind)
              height: width
              radius: Style.space(2)
              color: Model.heatColor(usage, root.pal.faint, root.pal.primary, root.pal.hot, 4)
              Behavior on color { ColorAnimation { duration: 320 } }
            }
          }
        }
      }
    }
  }
}
